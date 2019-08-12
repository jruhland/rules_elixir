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
                                       #default = Label("@rules_elixir//impl:mix_runner_template.exs"),
                                       default = Label("@rules_elixir//impl:new_mix_template.exs"),
                                       
    ),
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
    return dict([tup
                 for s in structures
                 for tup in s.items()
    ])
                 

# assumes that you have been passed _mix_project_attrs
def run_mix_task(ctx,
                 inputs = [],
                 deps = [],
                 outputs_map = [],
                 task = None,
                 args = None,
                 **kwargs):

    output_name = "{}_mix_{}".format(ctx.label.name, task)
    mix_runner = ctx.actions.declare_file("{}_runner.exs".format(output_name))
    outputs_str = structure_to_elixir(outputs_map)
    deps_structure = combine_structures([d[BuildOverlay].structure for d in deps])

    ctx.actions.expand_template(
        template = ctx.file._mix_runner_template,
        output = mix_runner,
        substitutions = {
            "{project_dir}": ctx.file.mixfile.dirname,
            "{outputs_list_body}": outputs_str,
            "{deps_list_body}": structure_to_elixir(deps_structure),
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
            [mix_runner]
            + ctx.files.mixfile
            + ctx.files.lockfile
            + ctx.files.apps_mixfiles
            + inputs
            + deps_structure.values()
        ),
        outputs = outputs_map.values(),
        use_default_shell_env = True,
        **kwargs
    )

################################################################
# `_mix_deps_compile` rule
# Invokes mix to compile a list of external dependencies, specified by name

_mix_deps_compile_attrs = {
    "deps_to_compile": attr.string_list(),
    "input_tree": attr.label_list(allow_files = True),
    "deps": attr.label_list(),
    "my_output_list": attr.output_list(allow_empty = True),
}

def _mix_deps_compile_impl(ctx):
    outputs_root = ctx.genfiles_dir.path + "/" + ctx.label.package + "/"
    outputs_rel = dict([(s.path[len(outputs_root):], s) for s in ctx.outputs.my_output_list])

    args = ctx.actions.args()
    args.add_all(ctx.attr.deps_to_compile)
    
    run_mix_task(
        ctx,
        inputs = ctx.files.input_tree,
        outputs_map = outputs_rel,
        deps = ctx.attr.deps,
        task = "deps.compile",
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

mix_deps_compile = rule(
    _mix_deps_compile_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items() + _mix_deps_compile_attrs.items()),
)


def merge(d, **kwargs):
    return dict(kwargs, **d)

def external_dep_target(dep_name):
    return "external_dep_" + dep_name


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

    buildfiles_globs = ["{}/{}".format(info["path"], build_file)
                        for info in deps_graph.values()
                        for build_file in ["mix.exs", "rebar.config"]]


    for dep_app, info in deps_graph.items():
        if info["in_umbrella"]:
            continue
        if len(info["inputs"]) == 1:
            mix_deps_compile(
                name = external_dep_target(dep_app),
                deps_to_compile = [dep_app],
                input_tree = native.glob(buildfiles_globs + ["{}/**".format(info["path"])]),
                my_output_list = ["_build/dev/lib/"+dep_app,
                                  "deps/"+dep_app,
                ],
                **mix_attrs
            )
        else:
            mix_deps_compile(
                name = external_dep_target(dep_app),
                deps_to_compile = [dep_app],
                deps = [external_dep_target(d) for d in info["deps"]],
                input_tree = native.glob(buildfiles_globs + ["{}/**".format(info["path"])]),
                my_output_list = ["_build/dev/lib/"+dep_app,
                                  "deps/"+dep_app,
                ],
                **mix_attrs
            )

            
        
