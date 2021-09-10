load("@rules_elixir//impl:providers.bzl", "OTPInfo")

def _find_otp_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            otpinfo = OTPInfo(
                # Cheat and construct a fake file object...no one will know the difference
                erl = struct(
                    path = ctx.attr.erl_path,
                    short_path = ctx.attr.erl_path,
                    owner = struct(
                        workspace_name = ctx.workspace_name,
                    ),
                    dirname = str(ctx.attr.erl_dir),
                    root = struct(
                        path = "",
                    ),
                ),
                files = depset([]),
                erts_version = ctx.attr.erts_version,
                c_headers = ctx.attr.erts_c_headers,
            ),
        ),
    ]

find_otp = rule(
    implementation = _find_otp_impl,
    attrs = {
        "erl_path": attr.string(
            doc = "The path to the `erl` executable from the system PATH",
        ),
        "erl_dir": attr.string(
            doc = """
            Dirname of same.  Does not need to actually point to the OTP bin directory; 
            we just need to know if erl is in /bin, /usr/local/bin, etc so that we can
            set up the PATH correctly later on
            """,
        ),
        "erts_version": attr.string(
            doc = """
            The ERTS version that comes with this release of erlang/OTP, like "10.4.4"
            """,
        ),
        "erts_c_headers": attr.label(
            providers = [CcInfo],
        ),
    },
)
