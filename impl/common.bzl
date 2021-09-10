ElixirLibrary = provider(
    doc = "Provider for analysis-phase information about Elixir compilation",
    fields = {
        "lib_dirs": """
        (depset of Files)
        One or more "lib dirs" for the application(s) comprising this library.
        The directory that is actually added to the code path is {lib_dir}/ebin, but
        other directories such as {lib_dir}/priv will also be available to dependents.
        Entries may also be .ez archives.
        """,
    },
)

elixir_common_attrs = {
    "_elixir_runfiles_bash": attr.label(
        allow_files = True,
        default = Label("@rules_elixir//:elixir_runfiles.bash"),
    ),
    "_elixir_locale": attr.string(default = "C.UTF-8"),
}
