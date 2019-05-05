load(":common.bzl", "ElixirLibrary", "elixir_common_attrs")

# attributes that we will need in the mix rules implementation
# some of these are computed in the `mix_project` macro (so we can glob)
_mix_project_attrs = {
    "mixfile":        attr.label(allow_single_file = ["mix.exs"]),
    "lockfile":       attr.label(allow_single_file = ["mix.lock"]),        
    "mix_env":        attr.string(),
    "build_path":     attr.string(),
    "deps_tree":      attr.label_list(allow_files = True),
    "deps_names":     attr.string_list(),
    "apps_names":     attr.string_list(),
    "apps_mixfiles":  attr.label_list(allow_files = True),
    "config_path":    attr.label(allow_single_file = True)
}

# We will produce fragments of the final _build directory in multiple separate steps,
# so we need this information to copy everything where it needs to go.
BuildOverlay = provider(
    doc = "Provider for a directory which mirrors the Mix _build structure",
    fields = {
        # "root_dir": "(File) the actual build directory, e.g. .../_build/dev",
        "structure": "(list<struct<relative: string, location: File>>) each logical subdirectory of the root and its real location",
    }
)

# helper to compute application ebin directories within the build directory
def ebin_for_app(app):
    return "lib/{}/ebin".format(app)

# assumes that you have been passed _mix_project_attrs
def declare_build_root(ctx):
    out_name = ctx.label.name + "/" + ctx.attr.build_path
    return (out_name, ctx.actions.declare_directory(out_name))

# assumes that you have been passed _mix_project_attrs
def invoke_elixir_for_mix(ctx,
               extra_inputs = [],
               **kwargs):
    ctx.actions.run(
        executable = ctx.executable._elixir_tool,
        inputs = (
            ctx.files.mixfile
            + ctx.files.lockfile
            + ctx.files.apps_mixfiles
            + ctx.files.deps_tree
            + extra_inputs
        ),
        env = {
            # mix needs the home directory to find Hex and rebar3
            "HOME": "/home/russell",
            "LANG": "en_US.UTF-8",
            "PATH": "/bin:/usr/bin:/usr/local/bin",
        },
        **kwargs
    )

def run_mix_task(ctx,
               extra_inputs = [],
               output_dir = None,
               extra_outputs = [],
               task = None,
               args = [],
               **kwargs):
    elixir_args = ctx.actions.args()
    elixir_args.add_all([
        "elixir", "-e",
        """
        dest = Path.absname("{out_dir}")
        File.cd!("{project_dir}")
        Mix.start
        Mix.CLI.main
        File.cd!("{build_path}")
        args = List.flatten ["-rL", File.ls!(), dest]
        0 = System.cmd("cp", args) |> elem(1)
        # IO.puts(:os.cmd(to_charlist("find " <> dest)))
        """.format(
            project_dir = ctx.file.mixfile.dirname,
            build_path = ctx.attr.build_path,
            out_dir = output_dir.path,
        ),
        task,
    ])

    ctx.actions.run(
        executable = ctx.executable._elixir_tool,
        arguments = [elixir_args, args],
        inputs = (
            ctx.files.mixfile
            + ctx.files.lockfile
            + ctx.files.apps_mixfiles
            + ctx.files.deps_tree
            + extra_inputs
        ),
        outputs = [output_dir] + extra_outputs,
        env = {
            # mix needs the home directory to find Hex and rebar3
            "HOME": "/home/russell",
            "LANG": "en_US.UTF-8",
            "PATH": "/bin:/usr/bin:/usr/local/bin",
        },
        **kwargs
    )




################################################################
# `mix_third_party_deps` rule
# compile ALL third_party deps as a single unit
# simpler to implement and avoids duplicate work if one dep depends on another
def _mix_third_party_deps_impl(ctx):
    out_name, out_dir = declare_build_root(ctx)

    # declare the structure of our generated _build directory and create the actual files
    subdirs = [ebin_for_app(dep) for dep in ctx.attr.deps_names]
    structure = [
        struct(
            relative = subdir,
            location = ctx.actions.declare_directory("{}/{}".format(out_name, subdir))
        )
        for subdir in subdirs
    ]
    ebin_dirs = [e.location for e in structure]
    
    run_mix_task(
        ctx,
        progress_message = "Compiling {} third-party Mix dependencies".format(len(ctx.attr.deps_names)),
        output_dir = out_dir,
        extra_outputs = ebin_dirs,
        task = "deps.compile",
        args = ctx.actions.args().add_all(ctx.attr.deps_names)
    )

    generated = depset(ebin_dirs)
    return [
        ElixirLibrary(
            loadpath = generated,
            runtime_deps = depset([]),
        ),
        BuildOverlay(
            # root_dir = out_dir,
            structure = structure,
        ),
        DefaultInfo(
            files = generated,
        )
    ]

mix_third_party_deps = rule(
    _mix_third_party_deps_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items()),
)

################################################################
# `elixir_link1` rule
# Compiles and "links" a single application into a build directory fragment
# in case of a regular Mix project, this is just called once for the single application
# in case of an umbrella it is called once for each child application
_elixir_link1_attrs = {
    "app_name": attr.string(),
    "libs": attr.label_list(),
}

def _elixir_link1_impl(ctx):
    out_name, out_dir = declare_build_root(ctx)

    subdir = ebin_for_app(ctx.attr.app_name)
    ebin_dir = ctx.actions.declare_directory("{}/{}".format(out_name, subdir))

    lib_loadpaths = depset(transitive = [lib[ElixirLibrary].loadpath for lib in ctx.attr.libs])
    ctx.actions.run_shell(
        inputs = lib_loadpaths,
        outputs = [out_dir, ebin_dir],
        arguments = [
            ctx.actions.args()
            .add(ebin_dir.path)
            .add_all(lib_loadpaths)
        ],
        command = """
        OUT=$1 ; shift
        cp $@ $OUT
        """
    )

    return [
        ElixirLibrary(
            loadpath = depset([ebin_dir]),
            runtime_deps = depset([]),
        ),
        BuildOverlay(
            structure = [
                struct(
                    relative = subdir,
                    location = ebin_dir
                ),
            ]
        ),
        DefaultInfo(
            files = depset([ebin_dir])
        ),
    ]

elixir_link1 = rule(
    _elixir_link1_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items() + _elixir_link1_attrs.items()),
)

################################################################
# `elixir_merge_overlays` rule
# "Linker" step where we combine multiple BuildOverlays into a single

_elixir_merge_overlays_attrs = {
    "overlays": attr.label_list(),
}

def overlay_entry_args(entry):
    return [entry.relative, entry.location.path]

def _elixir_merge_overlays_impl(ctx):
    out_name, out_dir = declare_build_root(ctx)
    combined_structure = [
        entry
        for overlay in ctx.attr.overlays
        for entry in overlay[BuildOverlay].structure
    ]

    ctx.actions.run_shell(
        inputs = [e.location for e in combined_structure],
        outputs = [out_dir],
        arguments = [
            ctx.actions.args()
            .add(out_dir.path)
            .add_all(combined_structure, map_each = overlay_entry_args),
        ],
        command = """
        OUT=$1 ; shift
        while (($#)); do
          REL=$OUT/$1 ; shift
          SRC=$1 ; shift
          mkdir -p $REL
          cp -rL $SRC/* $REL
        done
        """
    )

    return [
        DefaultInfo(
            files = depset([out_dir]),
        ),
        BuildOverlay(
            structure = combined_structure,
        )
    ]
    

elixir_merge_overlays = rule(
    _elixir_merge_overlays_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items() + _elixir_merge_overlays_attrs.items()),
)


################################################################
# `elixir_compile_app` rule
# step to invoke mix compile.app 
_mix_compile_app_attrs = {
    "apps": attr.string_list(),
}

def _mix_compile_app_impl(ctx):
    out_name, out_dir = declare_build_root(ctx)

    subdirs = [ebin_for_app(app) for app in ctx.attr.apps]
    structure = [
        struct(
            relative = subdir,
            location = ctx.actions.declare_directory("{}/{}".format(out_name, subdir))
        )
        for subdir in subdirs
    ]
    ebin_dirs = [e.location for e in structure]
    args = ctx.actions.args()
    args.add_all(["deps.loadpaths", "--no-deps-check", ",", "compile.app"])
    args.add_all(ctx.attr.apps)
    run_mix_task(
        ctx,
        output_dir = out_dir,
        extra_outputs = ebin_dirs,
        task = "do",
        args = args,
    )
    return [
        DefaultInfo(
            files = depset(ebin_dirs),
        ),
        BuildOverlay(
            structure = structure,
        ),
    ]

mix_compile_app = rule(
    _mix_compile_app_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items() + _mix_compile_app_attrs.items()),
)


################################################################
# SOURCES: the umbrella project compile_all target depends on the same target of all apps
# CONFIG: each child app depends on the config of the umbrella
# DEPS: each child app depends on the deps of the umbrella
# the reason that we care at all is so that we can build child apps individually?
################################################################

def merge(d, **kwargs):
    return dict(kwargs, **d)

def link_target(app):
    return app + "_link"

def mix_project(name = None,
                deps_path = None,
                apps_path = None,
                apps_targets = {},
                mix_env = None,
                **kwargs):

    mix_attrs = merge(
        kwargs,
        mixfile = "mix.exs",
        lockfile = "mix.lock",
        deps_tree = native.glob(["{}/**".format(deps_path)]),
        apps_mixfiles = native.glob(["{}/*/mix.exs".format(apps_path)]),
        visibility = ["//visibility:public"],
    )
    third_party_target = name + "_third_party"
    mix_third_party_deps(name = third_party_target, **mix_attrs)

    for app, targets in apps_targets.items():
        elixir_link1(
            name = link_target(app),
            app_name = app,
            libs = targets,
            **mix_attrs
        )
        
    compile_app_target = name + "_compile_app"
    mix_compile_app(
        name = compile_app_target,
        apps = apps_targets.keys(),
        **mix_attrs
    )

    elixir_merge_overlays(
        name = name + "_merged",
        overlays = [third_party_target, compile_app_target] + [link_target(app) for app in apps_targets.keys()],
        **mix_attrs
    )

