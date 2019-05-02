load(":common.bzl", "ElixirLibrary", "elixir_common_attrs")

# invoke the elixir compiler on `srcs`, producing a single ebin dir `out`
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

_elixir_library_attrs = {
    "srcs": attr.label_list(
        allow_files = [".ex"],
        doc = "Source files",
    ),
    "compile_deps": attr.label_list(),
    "runtime_deps": attr.label_list(),
}

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
        ),
        ElixirLibrary(
            loadpath = depset(
                direct = [ebin_dir],
                transitive = [runtime_loadpath]
            ),
        )
    ]

elixir_library = rule(
    _elixir_library_impl,
    attrs = dict(elixir_common_attrs.items() + _elixir_library_attrs.items()),
    doc = "Builds a directory containing .beam files for all modules in the source file(s)",
)

_elixir_script_attrs = {
    "srcs": attr.label_list(
        allow_files = [".ex", ".exs"],
        doc = "Source files",
    ),
    # since scripts don't have a separate compilation step, they just have `deps`,
    # unlike elixir_libraries, which must specify compile and runtime deps separately
    "deps": attr.label_list(),
    "_script_template": attr.label(
        allow_single_file = True,
        default = Label("//impl:elixir_script.template"),
    ),
}

# helper to find paths to our runfiles, might need to get smarter to work cross-platform... 
def _rlocation(ctx, runfile):
    # NOTE: Windows runfiles manifest file includes workspace name...
    # but if we have real symlinks they don't have workspace name... 
    #return "$(rlocation {}/{})".format(ctx.workspace_name, runfile.short_path)
    return runfile.short_path

def _elixir_script_impl(ctx):
    # collect all transitive loadpaths into runfiles, since we need them at runtime 
    lib_runfiles = ctx.runfiles(
        transitive_files = depset(
            transitive = [dep[ElixirLibrary].loadpath for dep in ctx.attr.deps]
        ),
    )
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


elixir_script_runner = rule(
    _elixir_script_impl,
    attrs = dict(elixir_common_attrs.items() + _elixir_script_attrs.items()),
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
