load(":common.bzl", "ElixirLibrary", "elixir_common_attrs")
load(":elixir_rules.bzl", "elixir_library")

# attributes that we will need in the mix rules implementation
# some of these are computed in the `mix_project` macro  
_mix_project_attrs = {
    "mixfile":        attr.label(allow_single_file = ["mix.exs"]),
    "lockfile":       attr.label(allow_single_file = ["mix.lock"]),        
    "mix_env":        attr.string(),
    "build_path":     attr.string(),
    "deps_tree":      attr.label_list(allow_files = True),
    "deps_names":     attr.string_list(),
    "apps_mixfiles":  attr.label_list(allow_files = True),
    "config_path":    attr.label(allow_single_file = True)
}
        
# implementation of mix_third_party_deps rule -- compile ALL third_party deps as a single unit
# simpler to implement and avoids duplicate work if one dep depends on another
def _mix_third_party_deps_impl(ctx):
    out_name = "third_party"
    # declare the root directory so that we know where bazel wants us to put everything
    out_dir = ctx.actions.declare_directory(out_name)
    # declare all ebin dirs that will be created so we can provide them with ElixirLibrary 
    ebin_dirs = [
        ctx.actions.declare_file(
            "{output}/{env}/lib/{pkg}/ebin".format(
                output = out_name,
                env = ctx.attr.mix_env,
                pkg = dep,
                )
        )
        for dep in ctx.attr.deps_names
    ]
    
    args = ctx.actions.args()
    args.add_all(["elixir", "-e",
        """
        File.cd!("{project_dir}", fn -> Mix.start; Mix.CLI.main; end)
        0 = System.cmd("cp", ["-r", "{project_dir}/{build_path}", "{out_dir}"]) |> elem(1)
        """.format(
            project_dir = ctx.file.mixfile.dirname,
            build_path = ctx.attr.build_path,
            out_dir = out_dir.path,
        ),
        "deps.compile",
    ])
    args.add_all(ctx.attr.deps_names)

    print("APPS MIXFILES ", ctx.files.apps_mixfiles)

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
            "HOME": "/Users/russell",
            "LANG": "en_US.UTF-8",
            "PATH": "/bin:/usr/bin:/usr/local/bin",
        }
    )

    return [
        ElixirLibrary(
            loadpath = depset(ebin_dirs),
            runtime_deps = depset([]),
        ),
        DefaultInfo(
            files = depset(ebin_dirs),
        )
    ]

mix_third_party_deps = rule(
    _mix_third_party_deps_impl,
    attrs = dict(elixir_common_attrs.items() + _mix_project_attrs.items()),
)

# SOURCES: the umbrella project compile_all target depends on the same target of all apps
# CONFIG: each child app depends on the config of the umbrella
# DEPS: each child app depends on the deps of the umbrella
# the reason that we care at all is so that we can build child apps individually?

def mix_project(name = None,
                deps_path = None,
                apps_path = None,
                lib_targets = [],
                **kwargs):

    third_party = name + "_third_party"

    mix_third_party_deps(
        name = third_party,
        mixfile = "mix.exs",
        lockfile = "mix.lock",
        deps_tree = native.glob(["{}/**".format(deps_path)]),
        apps_mixfiles = native.glob(["{}/*/mix.exs".format(apps_path)]),
        visibility = ["//visibility:public"],
        **kwargs
    )

    elixir_library(
        name = name + "_all",
        srcs = ["//impl:empty.ex"],
        macroexpand_deps = [third_party] + lib_targets,
        visibility = ["//visibility:public"],
    )
    


