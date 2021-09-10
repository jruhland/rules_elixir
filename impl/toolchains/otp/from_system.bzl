load("@rules_elixir//impl/toolchains/otp:common.bzl", "erts_headers_cc_library", "query_local_erlang_install")
load("@rules_elixir//impl/toolchains/otp:otp_version.bzl", "otp_versions")
# Repository rule which exposes erlang/OTP from your PATH as an erlang toolchain
# (or does nothing if you don't have it)

def _erlang_from_system_path_impl(ctx):
    info = query_local_erlang_install(ctx)
    if None == info or info.otp_version not in otp_versions:
        ctx.file("BUILD", "")
        return

    exec2 = ctx.execute([ctx.path(ctx.attr._copy_erts_headers_escript), "."])
    if exec2.return_code != 0:
        fail("Could not produce ERTS C headers: stderr {}, stdout {}".format(repr(exec2.stderr), repr(exec2.stdout)))

    ctx.file(
        "erts-{}/include/BUILD".format(info.erts_version),
        erts_headers_cc_library(info.erts_version),
    )

    ctx.template(
        "BUILD",
        ctx.path(ctx.attr._build_file_template),
        {
            "%%which_erl%%": str(info.which_erl),
            "%%dirname%%": str(info.which_erl.dirname),
            "%%erts_version%%": info.erts_version,
            "%%otp_version%%": info.otp_version,
            "%%erts_headers%%": "@{}//erts-{}/include:erts_headers".format(ctx.name, info.erts_version),
        },
    )

erlang_from_system_path = repository_rule(
    _erlang_from_system_path_impl,
    attrs = {
        "_build_file_template": attr.label(
            default = Label("@rules_elixir//impl/toolchains/otp:from_system.BUILD.template"),
        ),
        "_copy_erts_headers_escript": attr.label(
            default = Label("@rules_elixir//impl/toolchains/otp:copy_erts_headers.escript"),
            executable = True,
            cfg = "host",
        ),
    },
)
