load("@rules_elixir//impl:providers.bzl", "OTPInfo")

def _erlang_toolchain_impl(ctx):
    lib_dir = depset(ctx.files.lib_dir)
    erts_dir = depset(ctx.files.erts_dir)
    return [
        platform_common.ToolchainInfo(
            otpinfo = OTPInfo(
                otp_version = ctx.attr.otp_version,
                erts_version = ctx.attr.erts_version,
                lib_dir = lib_dir,
                erts_dir = erts_dir,
                erl = ctx.file.erl,
                files = depset(
                    direct = ctx.files.bin_dir,
                    transitive = [lib_dir, erts_dir],
                ),
            ),
        ),
    ]

erlang_toolchain = rule(
    _erlang_toolchain_impl,
    attrs = {
        "erts_version": attr.string(),
        "otp_version": attr.string(),
        "erl": attr.label(allow_single_file = True),
        "lib_dir": attr.label_list(allow_files = True),
        "erts_dir": attr.label_list(allow_files = True),
        "bin_dir": attr.label_list(allow_files = True),
    },
)
