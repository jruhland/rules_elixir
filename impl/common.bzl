ElixirLibrary = provider(
    doc = "Provider for analysis-phase information about Elixir compilation",
    fields = {
        "loadpath":
        """
        (depset of Files)
        Contains one or more `ebin` directories which contain `.beam` files
        for each module produced when compiling this library.  In other words,
        it contains the directories you need to have on your loadpath in order
        to find the compiled modules.
        """,

        "runtime_deps":
        """
        (depset of Targets)
        Contains references to other libraries that this library depends on
        at runtime only.  It must contain references (ie Targets) rather than
        actual generated files so as not to create circular deps, since circular
        runtime dependencies between modules are very much allowed in Elixir.
        """,

        "extra_sources":
        """
        huge hack for compile-time config
        """,
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
