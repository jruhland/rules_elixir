#load("@bazel_skylib//:lib.bzl", "shell")

ElixirLibrary = provider(
    # doc = "...",
    # fields = {
    #     "field": "doc"
    # }
)

def _elixir_loadpath_option(ebin_dir):
    return "-pa {}".format(ebin_dir)

def elixir_compile(ctx, srcs, out, deps = []):
    #print("elixir_compile deps = ", deps)
    transitive_deps = depset(transitive = [d.loadpath for d in deps])
    print("elixir_compile transitive deps = ", transitive_deps)
    args = ctx.actions.args()
    args.add_all(transitive_deps, expand_directories=False, before_each = "-pa")
    args.add("-o", out.path)
    args.add_all(srcs)
    ctx.actions.run_shell(
        outputs = [out],
        inputs = depset(direct = srcs, transitive = [transitive_deps]),
        command = "elixirc $@",
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
    return [
        DefaultInfo(files = depset([ebin_dir])),
        ElixirLibrary(
            loadpath = depset(
                direct = [ebin_dir],
                transitive = [dep[ElixirLibrary].loadpath for dep in ctx.attr.deps]
            )
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
    doc = "Builds",
)
