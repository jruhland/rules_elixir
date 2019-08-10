load(":common.bzl", "ElixirLibrary", "elixir_common_attrs")

# attributes that we will need in the mix rules implementation
# some of these are computed in the `mix_project` macro (so we can glob)
_mix_project_attrs = {
    "mixfile":        attr.label(allow_single_file = ["mix.exs"]),
    "lockfile":       attr.label(allow_single_file = ["mix.lock"]),
    "mix_env":        attr.string(),
    "build_path":     attr.string(),

    "external_projects": attr.string_dict(),
    # todo remove this and pass explicitly?
    "external_tree":     attr.label_list(allow_files = True),

    "apps_names":     attr.string_list(),
    "apps_mixfiles":  attr.label_list(allow_files = True),
    "config_path":    attr.label(allow_single_file = True),
    "config_tree":    attr.label_list(allow_files = True),
    "_mix_runner_template": attr.label(allow_single_file = True,
                                       default = Label("@rules_elixir//impl:mix_runner_template.exs")),
}

# We will produce fragments of the final _build directory in multiple separate steps,
# so we need this information to copy everything where it needs to go.
BuildOverlay = provider(
    doc = "Provider for a directory which mirrors the Mix _build structure",
    fields = {
        # "root_dir": "(File) the actual build directory, e.g. .../_build/dev",
        "structure": "(list<struct<app_name: string, relative: string, location: File>>) each logical subdirectory of the root and its real location",
    }
)

# assumes that you have been passed _mix_project_attrs
def declare_build_root(ctx):
    out_name = ctx.label.name + "/" + ctx.attr.build_path
    return (out_name, ctx.actions.declare_directory(out_name))

################################################################
# `elixir_merge_overlays` rule
# "Linker" step where we combine one or more BuildOverlays into a single BuildOverlay

_elixir_merge_overlays_attrs = {
    "overlays": attr.label_list(), # The overlays to merge
    "only": attr.string_list(default = []), # If non-empty, only this list of apps will be linked 
}

def overlay_entry_args(entry):
    return [entry.relative, entry.location.path]

def do_merge_overlays(ctx, deps, out_dir, only=[]):
    combined_structure = [
        entry
        for dep in deps
        for entry in dep[BuildOverlay].structure
        if (0 == len(only)) or entry.app_name in only
    ]
    args = ctx.actions.args()
    args.add(out_dir.path)
    args.add_all(combined_structure, map_each = overlay_entry_args)
    ctx.actions.run_shell(
        inputs = [e.location for e in combined_structure],
        outputs = [out_dir],
        arguments = [args],
        command = """
        set -e
        OUT=$1 ; shift
        mkdir -p $OUT
        touch $OUT/dummy
        while (($#)); do
          REL=$OUT/$1 ; shift
          SRC=$1 ; shift
          mkdir -p $REL
          #echo "doing copy (merge overlays)"
                
          # lol FIXME why does bsd cp not work?  it says permission denied... 
          gcp -r $SRC/* $REL
        done
        """
    )

    return [
        DefaultInfo(
            files = depset([out_dir]),
        ),
        BuildOverlay(
            structure = combined_structure,
        ),
        ElixirLibrary(
            loadpath = depset([e.location for e in combined_structure]),
            runtime_deps = depset([]),
        ),
    ]
    
def _elixir_merge_overlays_impl(ctx):
    out_name, out_dir = declare_build_root(ctx)
    return do_merge_overlays(ctx, ctx.attr.overlays, out_dir, only=ctx.attr.only)

elixir_merge_overlays = rule(
    _elixir_merge_overlays_impl,
    attrs = dict(elixir_common_attrs.items()
                 + _mix_project_attrs.items()
                 + _elixir_merge_overlays_attrs.items()),
)

# assumes that you have been passed _mix_project_attrs
def run_mix_task(ctx,
                 inputs = [],
                 deps = [],
                 output_dir = None,
                 extra_outputs = [],
                 task = None,
                 args = None,
                 extra_elixir_code = ":noop",
                 **kwargs):

    merged_overlays_dir = ctx.actions.declare_directory(
        "{}/{}_merged_deps".format(
            ctx.label.name,
            ctx.attr.build_path
            )
    )
    merged_overlays = do_merge_overlays(ctx, deps, merged_overlays_dir)
    
    mix_runner = ctx.actions.declare_file("{}/mix_{}_runner.exs".format(output_dir.path, task))
    ctx.actions.expand_template(
        template = ctx.file._mix_runner_template,
        output = mix_runner,
        substitutions = {
            "{out_dir}": output_dir.path,
            "{project_dir}": ctx.file.mixfile.dirname,
            "{deps_dir}": merged_overlays_dir.path,
            "{build_path}": ctx.attr.build_path,
            "{more}": extra_elixir_code,
        }
    )

    elixir_args = ctx.actions.args()
    elixir_args.add_all([
        "elixir",
        mix_runner.path,
        task,
    ])

    ctx.actions.run(
        executable = ctx.executable._elixir_tool,
        arguments = [elixir_args, args or ctx.actions.args()],
        inputs = (
            [mix_runner, merged_overlays_dir]
            + ctx.files.mixfile
            + ctx.files.lockfile
            + ctx.files.apps_mixfiles
            + inputs
        ),
        outputs = [output_dir] + extra_outputs,
        use_default_shell_env = True,
        **kwargs
    )

################################################################
# `_mix_deps_compile` rule
# Invokes mix to compile a list of external dependencies, specified by name

_mix_deps_compile_attrs = {
    "group_name": attr.string(),
    "deps_to_compile": attr.string_list(),
    "input_tree": attr.label_list(allow_files = True),
    "deps": attr.label_list(),
    #"provided": attr.string_list(default = []),
}

# helper to compute application ebin directories within the build directory
def ebin_for_app(app):
    return "lib/{}/ebin".format(app)

def _mix_deps_compile_impl(ctx):
    #out_name, out_dir = declare_build_root(ctx)
    out_name = ctx.label.name + "_compile"
    out_dir = ctx.actions.declare_directory(out_name)

    # declare the structure of our generated _build directory and create the actual files
    structure = [
        struct(
            app_name = dep,
            relative = ebin_for_app(dep),
            location = ctx.actions.declare_directory("{}/{}/{}".format(out_name, ctx.attr.build_path, ebin_for_app(dep)))
        )
        for dep in ctx.attr.deps_to_compile
    ]
    ebin_dirs = [e.location for e in structure]
    args = ctx.actions.args()
    # args.add("--no-deps-check")
    #args.add_all(["deps.tree", ",", "deps.compile"])
    args.add_all(ctx.attr.deps_to_compile)
    run_mix_task(
        ctx,
        progress_message = "Compiling {n} dependency projects in group {group}".format(
            #n = len(ctx.attr.deps_to_compile),
            n = ctx.attr.deps_to_compile,
            group = ctx.attr.group_name,
        ),
        output_dir = out_dir,
        inputs = ctx.files.input_tree,
        deps = ctx.attr.deps,
        extra_outputs = ebin_dirs,
        task = "deps.compile",
        args = args,
    )

    generated = depset(ebin_dirs)
    return [
        ElixirLibrary(
            loadpath = generated,
            runtime_deps = depset([]),
        ),
        BuildOverlay(
            structure = structure,
        ),
        DefaultInfo(
            files = generated,
        )
    ]

mix_deps_compile = rule(
    _mix_deps_compile_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items() + _mix_deps_compile_attrs.items()),
)


################################################################
# `elixir_link1` rule
# Compiles and "links" a single application into a build directory fragment
# in case of a regular Mix project, this is just called once for the single application
# in case of an umbrella it is called once for each child application
_elixir_link1_attrs = {
    "app_name": attr.string(),
    "sources": attr.label_list(), # "Source" libraries, compiled beams flattened into lib/app_name
    "overlays": attr.label_list(), # Dependency projects
}

def _elixir_link1_impl(ctx):
    out_name, out_dir = declare_build_root(ctx)

    subdir = ebin_for_app(ctx.attr.app_name)
    ebin_dir = ctx.actions.declare_directory("{}/{}".format(out_name, subdir))

    compiled_beams = depset(transitive = [lib.files for lib in ctx.attr.sources])
    args = ctx.actions.args()
    args.add(ebin_dir.path)
    args.add_all(compiled_beams, expand_directories = True)

    ctx.actions.run_shell(
        inputs = compiled_beams,
        outputs = [out_dir, ebin_dir],
        arguments = [args],
        command = """
        OUT=$1 ; shift
        gcp -r $@ $OUT
        """,
        use_default_shell_env = True,
    )

    return [
        ElixirLibrary(
            loadpath = depset([ebin_dir]),
            runtime_deps = depset([]),
        ),
        BuildOverlay(
            structure = [
                struct(
                    app_name = ctx.attr.app_name,
                    relative = subdir,
                    location = ebin_dir
                ),
            ],
        ),
        DefaultInfo(
            files = depset([out_dir])
        ),
    ]

elixir_link1 = rule(
    _elixir_link1_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items() + _elixir_link1_attrs.items()),
)


################################################################
# `mix_compile_app` rule
# step to invoke mix compile.app 
_mix_compile_app_attrs = {
    "apps": attr.string_list(),
}

def _mix_compile_app_impl(ctx):
    #out_name, out_dir = declare_build_root(ctx)
    out_name = ctx.label.name + "_compile_app"
    out_dir = ctx.actions.declare_directory(out_name)

    structure = [
        struct(
            app_name = app,
            relative = ebin_for_app(app),
            location = ctx.actions.declare_directory("{}/{}/{}".format(out_name, ctx.attr.build_path, ebin_for_app(app)))
        )
        for app in ctx.attr.apps
    ]
    ebin_dirs = [e.location for e in structure]

    args = ctx.actions.args()
    args.add_all(["deps.loadpaths", "--no-deps-check", ",", "compile.app"])
    args.add_all(ctx.attr.apps)

    run_mix_task(
        ctx,
        output_dir = out_dir,
        # TODO do we need this?
        # inputs = ctx.files.external_tree,
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
# `mix_gen_config` rule
# step to invoke mix compile.app and create dummy source file which
# loads the configuration at compile-time.
_mix_gen_config_attrs = {
    "apps": attr.string_list(),
}

def _mix_gen_config_impl(ctx):
    out_name, out_dir = declare_build_root(ctx)
    config_file = ctx.actions.declare_file("config_loader.exs")

    run_mix_task(
        ctx,
        #inputs = ctx.files.external_tree + ctx.files.config_tree,
        inputs = ctx.files.config_tree,
        output_dir = out_dir,
        extra_outputs = [config_file],
        task = "loadconfig",
        progress_message = "Loading static configuration",
        extra_elixir_code = """
        configs = 
          for app <- [{apps}] do
            {{app, :application.get_all_env(app)}}
          end
        File.write!("{config_file}", [":application.set_env ", inspect(configs, limit: :infinity)])
        """.format(
            config_file = config_file.path,
            apps = ", ".join([":" + app for app in ctx.attr.apps])
        )
    )
    return [
        DefaultInfo(
            files = depset([out_dir, config_file]),
        ),
        ElixirLibrary(
            loadpath = depset([]),
            extra_sources = [config_file],
        ),
    ]

mix_gen_config = rule(
    _mix_gen_config_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items() + _mix_gen_config_attrs.items()),
)

def merge(d, **kwargs):
    return dict(kwargs, **d)

def link_target(app):
    return app + "_link"

def external_group_target(group):
    return "external_" + group

def external_dep_target(dep_name):
    return "external_dep_" + dep_name

def umbrella_compile_target(app_name):
    return app_name + "_compile"

def all_build_files(external_projects):
    return native.glob(["{}/{}".format(path, build_file)
                        for (_, path) in external_projects.items()
                        for build_file in ["mix.exs", "rebar.config"]])

# The mix_project macro is responsible for understanding project-level information produced by autodeps (see read_mix.ex).
# Basically dependencies and configuration.  It has to be a macro because this is where we do all of the globs, and rules can't glob
def mix_project(name = None,
                apps_path = None,
                external_projects = {},
                deps_graph = {},
                apps_targets = {},
                mix_env = None,
                **kwargs):

    mix_attrs = merge(
        kwargs,
        mixfile = "mix.exs",
        lockfile = "mix.lock",
        # external_tree = native.glob(["{}/**".format(path) for (dep, path) in external_projects.items()]),
        external_tree = [],
        apps_mixfiles = native.glob(["{}/*/mix.exs".format(apps_path)]),
        config_tree = native.glob(["**/config/*.exs"]),
        visibility = ["//visibility:public"],
    )

    # I can't figure out how to get the deps.compile step to compile indirect deps (deps of deps) by themselves.
    # But, they do get compiled when we compile the direct deps that depend on them.
    # So if we keep track of which direct dep "provides" each indirect dep, then we can create targets that refer
    # to every dep, which is important so that source files can depend on only the deps that they need. 
    provided_deps = {}
    for (dep_app, info) in deps_graph.items():
        if info["top_level"] and (not info["in_umbrella"]):
            for d in info["inputs"]:
                if (not deps_graph[d]["top_level"]) and not (d in provided_deps):
                    print(d, "PROVIDED BY", dep_app)
                    provided_deps[d] = dep_app

    deps_targets = []
    for (dep_app, info) in deps_graph.items():
        if info["in_umbrella"]:
            pass
        elif dep_app in provided_deps:
            #print("USING PROVIDED", dep_app)
            elixir_merge_overlays(
                name = external_dep_target(dep_app),
                overlays = [external_dep_target(provided_deps[dep_app])],
                only = [dep_app],
                **mix_attrs
            )
        elif info["top_level"]:
            # Note that if two direct dependencies both depend on the same indirect dependency, that
            # indirect dependency may be compiled twice.
            input_globs = [
                "{}/**".format(deps_graph[d]["path"])
                for d in info["inputs"]
            ]
            deps_mixfiles = all_build_files(external_projects)
            inputs = depset(deps_mixfiles + native.glob(input_globs)) # This depset is a hack to remove duplicates
            deps_targets += [external_dep_target(dep_app)]
            #print("COMPILING TOP LEVEL", dep_app, info["inputs"])
            mix_deps_compile(
                name = external_dep_target(dep_app),
                group_name = dep_app,
                deps = [umbrella_compile_target(d) if deps_graph[d]["in_umbrella"] else external_dep_target(d) for d in info["deps"]],
                #deps = [external_dep_target(d) for d in info["deps"] if deps_graph[d]["top_level"]],

                # For some reason Mix does not like it when you ask it to just compile `dep_app` here.
                # It complains that the transitive deps have the wrong environment, but if you tell it
                # to compile all the transitive deps at once, then it's fine...
                #deps_to_compile = info["inputs"],
                deps_to_compile = [dep_app],
                input_tree = inputs,
                **mix_attrs
            )
        else:
            print("can't find", dep_app, " hopefully it is unused")

    # Each app in the umbrella gets its own link target
    for app, targets in apps_targets.items():
        elixir_link1(
            name = umbrella_compile_target(app),
            app_name = app,
            sources = targets,
            **mix_attrs
        )
        dep_overlays = [
            umbrella_compile_target(d) if deps_graph[d]["in_umbrella"] else external_dep_target(d)
            for d in deps_graph[app]["deps"]
            if d in deps_graph # this check needed becuase `d` could be e.g. a dep with only: [:test]
        ]
        elixir_merge_overlays(
            name = link_target(app),
            overlays = [umbrella_compile_target(app)] + dep_overlays,
            **mix_attrs
        )

    compile_app_target = "compile_app"
    mix_compile_app(
        name = compile_app_target,
        apps = apps_targets.keys(),
        **mix_attrs
    )

    # Generate configuration for everything in one step...
    gen_config_target = "config"
    mix_gen_config(
        name = gen_config_target,
        apps = apps_targets.keys() + external_projects.keys(),
        **mix_attrs
    )

    app_link_targets = [link_target(app) for app in apps_targets.keys()]
    external_dep_targets = [external_dep_target(d) for (d, info) in deps_graph.items() if (d not in provided_deps) and (not info["in_umbrella"])]
    elixir_merge_overlays(
        name = "project",
        overlays = [compile_app_target] + app_link_targets + external_dep_targets,
        **mix_attrs
    )

