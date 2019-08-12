load(":common.bzl", "ElixirLibrary", "elixir_common_attrs")

# attributes that we will need in the mix rules implementation
# some of these are computed in the `mix_project` macro (so we can glob)
_mix_project_attrs = {
    "mixfile":        attr.label(allow_single_file = ["mix.exs"]),
    "lockfile":       attr.label(allow_single_file = ["mix.lock"]),
    "mix_env":        attr.string(),
    "build_path":     attr.string(),

    "apps_names":     attr.string_list(),
    "apps_mixfiles":  attr.label_list(allow_files = True),
    "config_path":    attr.label(allow_single_file = True),
    "config_tree":    attr.label_list(allow_files = True),
    "_mix_runner_template": attr.label(
        allow_single_file = True,
        default = Label("@rules_elixir//impl:new_mix_template.exs"),
    ),
    "_mix_home": attr.label(
        default = Label("@rules_elixir//impl:localhex")
    )
}

# We will produce fragments of the final _build directory in multiple separate steps,
# so we need this information to copy everything where it needs to go.
BuildOverlay = provider(
    doc = "Provider for a directory which mirrors the Mix _build structure",
    fields = {
        # "root_dir": "(File) the actual build directory, e.g. .../_build/dev",
        #"structure": "(list<struct<app_name: string, relative: string, location: File>>) each logical subdirectory of the root and its real location",
        "structure": "xD"
    }
)

def structure_to_elixir(structure):
    return ",".join([
        "{" + repr(rel) + ", " + repr(f.path) + "}"
        for (rel, f) in structure.items()
    ])

def combine_structures(structures):
    return dict([
        tup
        for s in structures
        for tup in s.items()
    ])
                 

# assumes that you have been passed _mix_project_attrs
def run_mix_task(ctx,
                 inputs = [],
                 deps = [],
                 output_structure = [],
                 subdir = "", 
                 task = None,
                 args = None,
                 **kwargs):

    output_name = "{}_mix_{}".format(ctx.label.name, task)
    mix_runner = ctx.actions.declare_file("{}_runner.exs".format(output_name))
    deps_structure = combine_structures([d[BuildOverlay].structure for d in deps])

    ctx.actions.expand_template(
        template = ctx.file._mix_runner_template,
        output = mix_runner,
        substitutions = {
            "{project_dir}": ctx.file.mixfile.dirname,
            "{subdir}": subdir,
            "{outputs_list_body}": structure_to_elixir(output_structure),
            "{deps_list_body}": structure_to_elixir(deps_structure),
        }
    )

    elixir_args = ctx.actions.args()
    elixir_args.add_all([
        "elixir",
        mix_runner.path,
        task,
    ])

    mix_home = ctx.attr._mix_home.files.to_list()[0]
    ctx.actions.run(
        executable = ctx.executable._elixir_tool,
        arguments = [elixir_args, args or ctx.actions.args()],
        inputs = (
            [mix_runner, mix_home]
            + inputs
            + deps_structure.values()
            + ctx.files.mixfile
            + ctx.files.lockfile
            + ctx.files.apps_mixfiles
            + ctx.files.config_tree
        ),
        outputs = output_structure.values(),
        #use_default_shell_env = True,
        env = {
            "HOME": mix_home.path,
            "PATH": "/bin/:/usr/bin/:/usr/local/bin",
            "MIX_ENV": ctx.attr.mix_env,
        },
        **kwargs
    )

################################################################
# primitive mix invocation rule
# used to download hex and rebar and provide them to the real mix_task rule
# kind of a hack
_prim_mix_invoke_attrs = {
    "args": attr.string_list()
}

def _prim_mix_invoke_impl(ctx):
    mixhome = ctx.actions.declare_directory("fake_mix_home")
    prim_mix_script = """
    abs_home = Path.absname(System.get_env("HOME"))
    System.put_env("MIX_HOME", abs_home <> "/.mix")
    Mix.start
    Mix.CLI.main
    """
    
    ctx.actions.run(
        executable = ctx.executable._elixir_tool,
        arguments = ["elixir", "-e", prim_mix_script, "--"] + ctx.attr.args,
        outputs = [mixhome],
        env = {
            "HOME": mixhome.path
        },
    )

    return [
        DefaultInfo(
            files = depset([mixhome])
        ),
    ]

prim_mix_invoke = rule(
    _prim_mix_invoke_impl,
    attrs = dict(elixir_common_attrs.items() + _prim_mix_invoke_attrs.items()),
)


################################################################

_mix_task_attrs = {
    "prefix": attr.string(),
    "subdir": attr.string(default = ""),
    "task": attr.string(),
    "args": attr.string_list(),
    "input_tree": attr.label_list(allow_files = True),
    "deps": attr.label_list(),
    "my_output_list": attr.output_list(allow_empty = True),
}

def _mix_task_impl(ctx):
    package_component = ctx.label.package + "/" if len(ctx.label.package) > 0 else ""
    outputs_root = ctx.bin_dir.path + "/" + package_component + ctx.attr.prefix + "/"
    outputs_rel = dict([(s.path[len(outputs_root):], s) for s in ctx.outputs.my_output_list])
    args = ctx.actions.args()
    args.add_all(ctx.attr.args)
    
    run_mix_task(
        ctx,
        inputs = ctx.files.input_tree,
        output_structure = outputs_rel,
        deps = ctx.attr.deps,
        subdir = ctx.attr.subdir,
        task = ctx.attr.task,
        args = args,
    )

    return [
        DefaultInfo(
            files = depset(outputs_rel.values())
        ),
        BuildOverlay(
            structure = outputs_rel
        )
    ]

mix_task = rule(
    _mix_task_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items() + _mix_task_attrs.items()),
)

def merge(d, **kwargs):
    return dict(kwargs, **d)

def external_dep_target(dep_name):
    return "external_dep_" + dep_name

def target_for_app(app, info):
    c, _ = info["path"].split("/", maxsplit = 2)
    if c == "apps":
        return app
    elif c == "deps":
        return "third_party_" + app
    else: return "first_party_" + app

def mix_project(name = None,
                apps_path = None,
                deps_graph = {},
                apps_targets = {},
                mix_env = None,
                **kwargs):

    mix_attrs = merge(
        kwargs,
        mix_env = mix_env,
        mixfile = "mix.exs",
        lockfile = "mix.lock",
        apps_mixfiles = native.glob(["{}/{}".format(info["path"], build_file)
                                     for info in deps_graph.values()
                                     for build_file in ["mix.exs", "rebar.config",
                                                        "rebar.config.script", "rebar.lock",
                                                        "Makefile",
                                     ]]),
        config_tree = native.glob(["**/config/*.exs"]),
        visibility = ["//visibility:public"],
    )

    apps_targets = dict([
        (app, name + "_" + target_for_app(app, info))
        for (app, info) in deps_graph.items()
    ])

    for dep_app, info in deps_graph.items():
        if info["in_umbrella"]:
            mix_task(
                name = apps_targets[dep_app],
                subdir = "apps/" + dep_app,
                task = "compile",
                args = ["--no-deps-check"],
                deps = [apps_targets[d] for d in info["inputs"] if d != dep_app],
                input_tree = native.glob(["{}/**".format(info["path"])]),
                prefix = name,
                my_output_list = ["{}/_build/{}/lib/{}".format(name, mix_env, dep_app)],
                **mix_attrs
            )
        else:
            mix_task(
                name = apps_targets[dep_app],
                task = "deps.compile",
                args = [dep_app],
                deps = [apps_targets[d] for d in info["inputs"] if d != dep_app],
                input_tree = native.glob(["{}/**".format(info["path"])]),
                # deps that are not managed by mix are compiled in place, so we have to re-export their source directory
                prefix = name,
                my_output_list = ["{}/_build/{}/lib/{}".format(name, mix_env, dep_app)] + (["{}/deps/{}".format(name, dep_app)] if "manager" in info and info["manager"] != "mix" else []),
                **mix_attrs
            )

    mix_task(
        name = name + "_compile",
        task = "compile",
        args = ["--no-deps-check"],
        deps = [apps_targets[d] for d in deps_graph.keys()],
        prefix = name,
        my_output_list = ["{}/_build/{}/consolidated".format(name, mix_env)],
        **mix_attrs
    )

    

