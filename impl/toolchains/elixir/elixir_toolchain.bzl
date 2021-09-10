load("@rules_elixir//impl:common.bzl", "ElixirLibrary")

def _elixir_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            elixirinfo = ctx.attr.elixir[ElixirLibrary],
        ),
    ]

elixir_toolchain = rule(
    _elixir_toolchain_impl,
    attrs = {
        "elixir": attr.label(
            providers = [ElixirLibrary],
            doc = "Elixir itself is just another ElixirLibrary",
        ),
    },
)
