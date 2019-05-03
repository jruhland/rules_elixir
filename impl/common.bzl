ElixirLibrary = provider(
    doc = "Provider for compiled .beam modules stored in `ebin` directories",
    fields = {
        "loadpath": "depset of `ebin` directories",
        "runtime_deps": "yeah",
    }
)

# we need to make an attribute with the default value of a Label in order to
# introduce an implicit dependency on elixir itself
elixir_common_attrs = {
    "_elixir_tool": attr.label(
        executable = True,
        cfg = "host",
        default = Label("@elixir//:elixir_tool"),
    ),
}
