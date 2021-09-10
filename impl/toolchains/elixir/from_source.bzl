def _elixir_source_archive_impl(ctx):
    ctx.download_and_extract(
        url = ctx.attr.url,
        sha256 = ctx.attr.sha256,
        stripPrefix = "elixir-{}".format(ctx.attr.version),
    )
    ctx.template(
        "BUILD",
        ctx.path(ctx.attr._build_file_template),
        {
            "%%name%%": ctx.name,
            "%%version%%": ctx.attr.version,
        },
    )

elixir_source_archive = repository_rule(
    _elixir_source_archive_impl,
    attrs = {
        "url": attr.string(),
        "sha256": attr.string(),
        "version": attr.string(),
        "_build_file_template": attr.label(
            default = Label("@rules_elixir//impl/toolchains/elixir:from_source.BUILD.template"),
        ),
    },
)
