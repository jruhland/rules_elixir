load(":common.bzl", "erts_headers_cc_library", "query_erlang_version_info", "query_local_erlang_install")

# Repository rule to expose a binary OTP release which was already compiled outside of bazel,
# as an erlang_toolchain.
def _prebuilt_otp_release_impl(ctx):
    if ctx.os.name != ctx.attr.repository_os:
        ctx.file("BUILD", "")
        return

    local_erlang = query_local_erlang_install(ctx)
    if None != local_erlang and local_erlang.otp_version == ctx.attr.otp_version:
        ctx.file("BUILD", "")
        return

    build_file_template = ctx.path(ctx.attr._build_file_template)
    ctx.download_and_extract(
        url = ctx.attr.url,
        sha256 = ctx.attr.sha256,
        stripPrefix = ctx.attr.strip_prefix,
    )

    er = ctx.execute([ctx.path("Install"), str(ctx.path("."))])
    if er.return_code != 0:
        fail("Could not install OTP release" + er.stderr)

    info = query_erlang_version_info(ctx, ctx.path("bin/erl"))
    if info.otp_version != ctx.attr.otp_version:
        fail("OTP version mismatch.  Rule claims to download {claim} but it is actually {actual}".format(
            claim = ctx.attr.otp_version,
            actual = info.otp_version,
        ))

    # template a BUILD file to expose the files and version information in the OTPInfo provider.
    ctx.template(
        "BUILD",
        ctx.path(ctx.attr._build_file_template),
        {
            "%%name%%": ctx.name,
            "%%erts_version%%": info.erts_version,
            "%%otp_version%%": info.otp_version,
            "%%compatible_with%%": repr(
                [str(s) for s in ctx.attr.compatible_with] +
                ["@rules_elixir//impl/toolchains/otp:{}".format(info.otp_version)],
            ),
        },
    )
    ctx.file(
        "erts-{}/include/BUILD".format(info.erts_version),
        erts_headers_cc_library(info.erts_version),
    )

prebuilt_otp_release = repository_rule(
    _prebuilt_otp_release_impl,
    doc = """
    Rule to expose a prebuilt OTP release as an erlang toolchain.  
    To build an OTP release that can be used with this rule, you can use e.g.
    `make RELEASE_ROOT=/path/to/release release`
    after you have built OTP.  Then, create an archive with all the files
    from /path/to/release under a prefix like otp-release-22.0.7
    """,
    attrs = {
        "url": attr.string(),
        "sha256": attr.string(),
        "strip_prefix": attr.string(),
        "repository_os": attr.string(
            doc = "This rule will do nothing if the value of repository_ctx.os.name does not match this attr",
        ),
        # `compatible_with` (attribute common to all rules) is also expected
        "otp_version": attr.string(
            doc = """
            OTP version (e.g. 22.0.7).
            If a matching version is installed locally ,this rule will do nothing (use erlang_from_system_path to expose it).
            If the download OTP release does not match, this rule will fail.
            """,
        ),
        "_build_file_template": attr.label(
            default = Label("@rules_elixir//impl/toolchains/otp:prebuilt.BUILD.template"),
        ),
        "_copy_erts_headers_escript": attr.label(
            default = Label("@rules_elixir//impl/toolchains/otp:copy_erts_headers.escript"),
            executable = True,
            cfg = "host",
        ),
    },
)
