load(":common.bzl", "ElixirLibrary", "elixir_common_attrs")

# attributes that we will need in the mix rules implementation
# some of these are computed in the `mix_project` macro  
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


# We will invoke Mix to compile the third_party deps for us, but we still
# need some information to copy the compiled deps into our generated _build dir later
BuildOverlay = provider(
    doc = "Provider for a directory which mirrors the Mix _build structure",
    fields = {
        # "root_dir": "(File) the actual build directory, e.g. .../_build/dev",
        "structure": "(list<struct<relative: string, location: File>>) each logical subdirectory of the root and its real location",
    }
)

def ebin_for_app(app):
    return "lib/{}/ebin".format(app)

# assumes that you have been passed _mix_project_attrs
def declare_build_root(ctx):
    out_name = ctx.label.name + "/" + ctx.attr.build_path
    return (out_name, ctx.actions.declare_directory(out_name))

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
    
    args = ctx.actions.args()
    args.add_all([
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
            out_dir = out_dir.path,
        ),
        "deps.compile",
    ])
    args.add_all(ctx.attr.deps_names)
    ctx.actions.run(
        executable = ctx.executable._elixir_tool,
        inputs = (
            ctx.files.mixfile
            + ctx.files.lockfile
            + ctx.files.apps_mixfiles
            + ctx.files.deps_tree
        ),
        progress_message = "Compiling {} third-party Mix dependencies".format(len(ctx.attr.deps_names)),
        outputs = [out_dir] + ebin_dirs,
        arguments = [args],
        env = {
            # mix needs the home directory to find Hex and rebar3
            "HOME": "/home/russell",
            "LANG": "en_US.UTF-8",
            "PATH": "/bin:/usr/bin:/usr/local/bin",
        }
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
    
_elixir_link_attrs = {
    "app": attr.string(),
    "mix_env": attr.string(),
    "third_party": attr.label(),
    "libs": attr.label_list(),
    "dirname": attr.string(
        default = "_build",
    ),
}

def _elixir_link_impl(ctx):
    root_dir_name = ctx.attr.build_path

    out_dir = ctx.actions.declare_directory(root_dir_name)

    ebin_dir = ctx.actions.declare_directory(
        "{}/lib/{}/ebin".format(root_dir_name, ctx.attr.app)
    )
    
    precompiled_deps = depset(
        transitive = [dep[ElixirLibrary].loadpath for dep in ctx.attr.libs]
    )
    # Link time is when we traverse the runtime depset and force runtime deps to be compiled   
    runtime_dep_targets = depset(
        transitive = [dep[ElixirLibrary].runtime_deps for dep in ctx.attr.libs]
    )
    compiled_runtime_deps = depset(
        transitive = [dep[ElixirLibrary].loadpath for dep in runtime_dep_targets.to_list()]
    )
    third_party_root_dir = ctx.attr.third_party[BuildOverlay].root_dir
    third_party_app_dirs = dict([
        (app, ctx.actions.declare_directory("{}/lib/{}/ebin".format(root_dir_name, app)))
        for app, _ in ctx.attr.third_party[BuildOverlay].app_dirs.items()
    ])
    
    modules_to_link = depset(
        direct = [third_party_root_dir],
        transitive = [precompiled_deps, compiled_runtime_deps],
    )
    ctx.actions.run_shell(
        inputs = modules_to_link,
        outputs = [out_dir, ebin_dir] + third_party_app_dirs.values(),
        arguments = [
            ctx.actions.args()
            .add(out_dir.path)
            .add(ebin_dir.path)
            .add(ctx.attr.mix_env)
            .add(third_party_root_dir.path)
            .add_all(precompiled_deps)
            .add_all(compiled_runtime_deps),
        ],
        command = """
        set -x
        ROOT=$1        ; shift
        LOCAL_EBIN=$1  ; shift
        MIX_ENV=$1     ; shift
        THIRD_PARTY=$1 ; shift
        cp -r $THIRD_PARTY/$MIX_ENV/* $ROOT
        # since we copy all of OUR compiled code in one `cp`, we should be safe
        # from trying to copy multiple files into the same-named beam file
        cp $@ $LOCAL_EBIN
        find $THIRD_PARTY
        """
    )

    return [
        DefaultInfo(
            files = depset([out_dir]),
        ),
        ElixirLibrary(
            loadpath = depset(
                direct = [ebin_dir] + third_party_app_dirs.values(),
            ),
            runtime_deps = depset([]),
        ),
        BuildOverlay(
            root_dir = out_dir,
            app_dirs = dict([(ctx.attr.app, ebin_dir)] + third_party_app_dirs.items()),
        ),
    ]
    

elixir_link = rule(
    _elixir_link_impl,
    attrs = dict(elixir_common_attrs.items() + _elixir_link_attrs.items()),    
)


################################################################

_mix_compile_app_attrs = {
    "build_directory": attr.label(
        doc = "label of the `elixir_link` that generates the _build directory"
    ),
}

def _mix_compile_app_impl(ctx):
    input_build_directory = ctx.attr.build_directory[BuildOverlay].root_dir.path
    root_dir_name = "{}/{}".format(ctx.label.name, ctx.attr.build_path)
    print("input_build_directory", input_build_directory)
    print("root_dir_name", root_dir_name)
    app_files = dict([
        (app, ctx.actions.declare_file("{root}/lib/{app}/ebin/{app}.app".format(
            root = root_dir_name,
            app = app,
        )))
        for app in ctx.attr.apps_names
    ])
    
    print("app_files = ", app_files)
    args = ctx.actions.args()
    # this is the part where we use string.format to construct elixir data structures
    s = "[" + ",".join(["{{\"{}\", \"{}\"}}".format(k, v.path) for k, v in app_files.items()]) + "]"
    args.add_all([
        "elixir", "-e",
        """
        IO.inspect(System.argv, label: "args")
        IO.inspect({app_files}, label: "app_files")
        
        """.format(
            app_files = s,
        ),
        "do",
        "loadpaths",
        "--no-deps-check",
        ",",
        "compile.app",
    ])
    args.add_all([app for app in app_files.keys()])
    ctx.actions.run(
        executable = ctx.executable._elixir_tool,
        inputs = ctx.files.apps_mixfiles + ctx.files.deps_tree + [
            ctx.attr.build_directory[BuildOverlay].root_dir,
            ctx.file.mixfile,
            ctx.file.lockfile,
        ],
        outputs = app_files.values(),
        arguments = [args],
        env = {
            # mix needs the home directory to find Hex and rebar3
            "HOME": "/home/russell",
            "LANG": "en_US.UTF-8",
            "PATH": "/bin:/usr/bin:/usr/local/bin",
        }
    )

    return [
        DefaultInfo(
            files =  depset(app_files.values()),
        )
    ]

mix_compile_app = rule(
    _mix_compile_app_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items() + _mix_compile_app_attrs.items()),
)


# SOURCES: the umbrella project compile_all target depends on the same target of all apps
# CONFIG: each child app depends on the config of the umbrella
# DEPS: each child app depends on the deps of the umbrella
# the reason that we care at all is so that we can build child apps individually?

################################################################
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
        set -x
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

def merge(d, **kwargs):
    return dict(kwargs, **d)

def mix_project(name = None,
                deps_path = None,
                apps_path = None,
                apps_targets = {},
                mix_env = None,
                **kwargs):

    third_party = name + "_third_party"

    mix_attrs = merge(kwargs,
                      mixfile = "mix.exs",
                      lockfile = "mix.lock",
                      deps_tree = native.glob(["{}/**".format(deps_path)]),
                      apps_mixfiles = native.glob(["{}/*/mix.exs".format(apps_path)]),
                      visibility = ["//visibility:public"],
    )

    mix_third_party_deps(name = third_party, **mix_attrs)

    app_link_targets = []
    for app, targets in apps_targets.items():
        link_target = app + "_link"
        app_link_targets.append(link_target)
        elixir_link1(
            name = link_target,
            app_name = app,
            libs = targets,
            **mix_attrs
        )
        
    elixir_merge_overlays(
        name = name + "_merged",
        overlays = [third_party] + app_link_targets,
        **mix_attrs
    )

    # elixir_link(
    #     name = name + "_all",
    #     app = name,
    #     third_party = third_party,
    #     libs = lib_targets,
    #     visibility = ["//visibility:public"],
    # )

    # mix_compile_app(
    #     name = name + "_compile_app",
    #     build_directory = name + "_third_party",
    #     **mix_attrs
    # )


