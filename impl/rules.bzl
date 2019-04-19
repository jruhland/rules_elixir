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
            "exec /usr/bin/elixir {} {} $@".format(
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


def _mix_project_impl(ctx):
    print("elixirc_files = ,", ctx.files.elixirc_files)
    
    f = ctx.actions.declare_file("whatever")
    ctx.actions.write(
        output = f,
        content = "whatever"
    )
    return [
        DefaultInfo(files = depset([f]))
    ]

mix_project_rule = rule(
    _mix_project_impl,
    attrs = {
        "mixfile": attr.label(
            allow_single_file = ["mix.exs"],
        ),
        "elixirc_files": attr.label_list(
            allow_files = True
        ),
    }
)

def mix_project(name = None,
                elixirc_paths = [],
                **kwargs):
    mix_project_rule(
        name = name,
        mixfile = "mix.exs",
        elixirc_files = native.glob([d + "/**" for d in elixirc_paths]),
        **kwargs
    )



