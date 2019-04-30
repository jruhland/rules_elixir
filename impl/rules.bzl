ElixirLibrary = provider(
    # doc = "...",
    # fields = {
    #     "field": "doc"
    # }
)

def elixir_compile(ctx, srcs, out, loadpath = []):
    args = ctx.actions.args()
    args.add("elixirc")
    args.add_all(loadpath, expand_directories=False, before_each = "-pa")
    args.add("-o", out.path)
    args.add_all(srcs)
    ctx.actions.run(
        executable = ctx.executable._elixir_tool,
        outputs = [out],
        inputs = depset(direct = srcs, transitive = [loadpath]),
        arguments = [args],
        env = {"HOME": ".",
               "LANG": "en_US.UTF-8"}
    )

def _elixir_library_impl(ctx):
    ebin_dir = ctx.actions.declare_directory(ctx.label.name + "_ebin")
    compile_loadpath = depset(transitive = [dep[ElixirLibrary].loadpath for dep in ctx.attr.compile_deps])
    elixir_compile(
        ctx,
        srcs = ctx.files.srcs,
        loadpath = compile_loadpath,
        out = ebin_dir,
    )
    runtime_loadpath = depset(transitive = [dep[ElixirLibrary].loadpath for dep in ctx.attr.runtime_deps])
    return [
        DefaultInfo(
            files = depset([ebin_dir]),
            default_runfiles = ctx.runfiles(
                files = [ebin_dir],
                transitive_files = runtime_loadpath,
            )
        ),
        ElixirLibrary(
            loadpath = depset(
                direct = [ebin_dir],
                transitive = [runtime_loadpath]
            ),
        )
    ]

_elixir_common_attrs = {
    "_elixir_tool": attr.label(
        executable = True,
        cfg = "host",
        default = Label("@elixir//:elixir_tool"),
    ),
}

_elixir_library_attrs = {
    "srcs": attr.label_list(
        allow_files = [".ex"],
        doc = "Source files",
    ),
    "deps": attr.label_list(),
    "compile_deps": attr.label_list(),
    "runtime_deps": attr.label_list(),
}

elixir_library = rule(
    _elixir_library_impl,
    attrs = dict(_elixir_common_attrs.items() + _elixir_library_attrs.items()),
    doc = "Builds a directory containing .beam files for all modules in the source file(s)",
)

def _rlocation(ctx, runfile):
    # NOTE: Windows runfiles manifest file includes workspace name...
    # but if we have real symlinks they don't have workspace name... 
    #return "$(rlocation {}/{})".format(ctx.workspace_name, runfile.short_path)
    return runfile.short_path

def _elixir_script_impl(ctx):
    lib_runfiles = ctx.runfiles(collect_default = True, collect_data = True)
    src_runfiles = ctx.runfiles(files = ctx.files.srcs)

    ctx.actions.expand_template(
        template = ctx.file._script_template,
        output = ctx.outputs.executable,
        substitutions = {
            "{elixir_tool}": ctx.executable._elixir_tool.path,
            "{loadpath}":    " ".join(["-pa {}".format(_rlocation(ctx, f)) for f in lib_runfiles.files]),
            "{srcs}":        " ".join([_rlocation(ctx, f) for f in src_runfiles.files]),
        },
        is_executable = True,
    )
    return [
        DefaultInfo(runfiles = src_runfiles.merge(lib_runfiles))
    ]

_elixir_script_attrs = {
    "srcs": attr.label_list(
        allow_files = [".ex", ".exs"],
        doc = "Source files",
    ),
    "deps": attr.label_list(),
    "_script_template": attr.label(
        allow_single_file = True,
        default = Label("//impl:elixir_script.template"),
    ),
}

elixir_script_runner = rule(
    _elixir_script_impl,
    attrs = dict(_elixir_common_attrs.items() + _elixir_script_attrs.items()),
    executable = True,
    doc = "Elixir script, intended for use with `bazel run` -- does not work outside bazel context"
)

def elixir_script(name = None, **kwargs):
    runner = name + "_runner"
    elixir_script_runner(name = runner, **kwargs)
    native.sh_binary(
        name = name,
        deps = ["@bazel_tools//tools/bash/runfiles", "@elixir//:elixir_tool_lib"],
        srcs = [runner],
        visibility = ["//visibility:public"],
    )
        
#_mix_project_deps_impl?
def _mix_project_impl(ctx):
    out = ctx.actions.declare_directory("third_party")
    #out = ctx.actions.declare_directory(ctx.attr.build_path)
    args = ctx.actions.args()
    args.add_all(["elixir", "-e",
        """
        Mix.start
        Mix.CLI.main
        # Copy because I'm not clever enough to set up the symlinks
        # System cp because File.cp_r does not follow links 
        System.cmd("cp", ["-r", "{build_path}", "{out_dir}"])
        """.format(
            out_dir = out.path,
            build_path = ctx.attr.build_path,
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
        outputs = [out],
        arguments = [args],
        env = {"HOME": "/Users/russell",
               "LANG": "en_US.UTF-8",
               "PATH": "/bin:/usr/bin:/usr/local/bin"}
    )
    return [
        DefaultInfo(files = depset([out]))
    ]

_mix_project_attrs = {
    "mixfile":  attr.label(allow_single_file = ["mix.exs"]),
    "lockfile": attr.label(allow_single_file = ["mix.lock"]),        
    "elixirc_files": attr.label_list(
        allow_files = True,
    ),
    "build_path": attr.string(),
    "deps_tree": attr.label_list(
        allow_files = True,
    ),
    "deps_names": attr.string_list(),
    "apps_mixfiles": attr.label_list(allow_files = True),
    "config_path": attr.label(
        allow_single_file = True,
    )
}

mix_project_rule = rule(
    _mix_project_impl,
    attrs = dict(_elixir_common_attrs.items() + _mix_project_attrs.items()),
)

def mix_project(name = None,
                elixirc_paths = [],
                deps_path = None,
                apps_path = None,
                **kwargs):
    print("kwargs = ", kwargs)
    mix_project_rule(
        name = name,
        mixfile = "mix.exs",
        lockfile = "mix.lock",
        elixirc_files = native.glob([d + "/**" for d in elixirc_paths]),
        deps_tree = native.glob(["{}/**".format(deps_path)]),
        apps_mixfiles = native.glob(["{}/*/mix.exs".format(apps_path)]),
        **kwargs
    )


# Third-party dependencies don't change very much, and might be built in weird ways.
# So for simplicity's sake, we are fine just building them with mix all at once



