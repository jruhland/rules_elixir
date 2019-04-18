ElixirLibrary = provider(
    # doc = "...",
    # fields = {
    #     "field": "doc"
    # }
)

def elixir_compile(ctx, srcs, out, deps = []):
    transitive_deps = depset(transitive = [d.loadpath for d in deps])
    args = ctx.actions.args()
    args.add_all(transitive_deps, expand_directories=False, before_each = "-pa")
    args.add("-o", out.path)
    args.add_all(srcs)
    ctx.actions.run_shell(
        outputs = [out],
        inputs = depset(direct = srcs, transitive = [transitive_deps]),
        command = "exec elixirc $@",
        arguments = [args],
        env = {"HOME": ".",
               "LANG": "en_US.UTF-8",
               "PATH": "/usr/bin"}
    )

def _elixir_library_impl(ctx):
    ebin_dir = ctx.actions.declare_directory(ctx.label.name + "_ebin")
    elixir_compile(
        ctx,
        srcs = ctx.files.srcs,
        deps = [dep[ElixirLibrary] for dep in ctx.attr.deps],
        out = ebin_dir,
    )
    transitive_paths = [dep[ElixirLibrary].loadpath for dep in ctx.attr.deps]
    return [
        DefaultInfo(
            files = depset([ebin_dir]),
            default_runfiles = ctx.runfiles(files = [ebin_dir],
                                            transitive_files = depset(transitive = transitive_paths)),
        ),
        ElixirLibrary(
            loadpath = depset(
                direct = [ebin_dir],
                transitive = transitive_paths
            ),
        )
    ]

    
elixir_library = rule(
    _elixir_library_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".ex"],
            doc = "Source files",
        ),
        "deps": attr.label_list(),
    },
    doc = "Builds a folder with .beam files for each module in the source file(s)",
)

def _elixir_script_impl(ctx):
    lib_runfiles = ctx.runfiles(collect_default = True)
    src_runfiles = ctx.runfiles(files = ctx.files.srcs)
    ctx.actions.write(
        output = ctx.outputs.executable,
        content = "\n".join([
            "#!/bin/sh",
            "exec elixir {} {} $@".format(
                " ".join(["-pa {}".format(d.short_path) for d in lib_runfiles.files]),
                " ".join([file.path for file in src_runfiles.files])),
            "\n",
        ]),
        is_executable = True,
    )

    return [
        DefaultInfo(runfiles = src_runfiles.merge(lib_runfiles))
    ]

elixir_script = rule(
    _elixir_script_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".ex"],
            doc = "Source files",
        ),
        "deps": attr.label_list(),
    },
    executable = True,
    doc = "Elixir script, intended for use with `bazel run` -- does not work outside bazel context"
)
