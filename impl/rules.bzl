load("@bazel_skylib//:lib.bzl", "shell")

ElixirLibrary = provider(
    # doc = "...",
    # fields = {
    #     "field": "doc"
    # }
)

def elixir_compile(ctx, srcs, out):
    cmd = "elixirc -o {out} {srcs}".format(
        out = shell.quote(out.path),
        srcs = " ".join([shell.quote(src.path) for src in srcs]),
    )
    ctx.actions.run_shell(
        outputs = [out],
        inputs = srcs,
        command = cmd,
        mnemonic = "elixirc",
        env = {"HOME": ".",
               "LANG": "en_US.UTF-8",
               "PATH": "/usr/bin"}
    )

def _elixir_library_impl(ctx):
    ebin_dir = ctx.actions.declare_directory(ctx.label.name + "_ebin")
    elixir_compile(
        ctx,
        srcs = ctx.files.srcs,
        out = ebin_dir,
    )

    return [DefaultInfo(
        files = depset([ebin_dir]),
    )]

elixir_library = rule(
    _elixir_library_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".ex"],
            doc = "Source files",
        ),
    },
    doc = "Builds",
)
