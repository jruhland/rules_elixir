load("@rules_elixir//impl:providers.bzl", "OTPInfo")

def _erts_headers_impl(ctx):
    erlang_toolchain = ctx.toolchains["@rules_elixir//impl/toolchains/otp:toolchain_type"].otpinfo
    return [
        erlang_toolchain.c_headers[CcInfo],
        erlang_toolchain.c_headers[OutputGroupInfo],
    ]

erts_headers = rule(
    _erts_headers_impl,
    attrs = {},
    toolchains = [
        "@rules_elixir//impl/toolchains/otp:toolchain_type",
    ],
    doc = """
    Resolves the OTP toolchain as normal and acts as a proxy for the cc_library which includes
    the ERTS header files.  You need to include these headers to build shared objects which you
    want to load in erlang, such as NIFs and port drivers.  
    """,
)

def _erts_headers_filegroup_impl(ctx):
    erlang_toolchain = ctx.toolchains["@rules_elixir//impl/toolchains/otp:toolchain_type"].otpinfo
    return [
        DefaultInfo(
            files = depset(erlang_toolchain.c_headers[CcInfo].compilation_context.headers),
        ),
    ]

erts_headers_filegroup = rule(
    _erts_headers_filegroup_impl,
    attrs = {},
    toolchains = [
        "@rules_elixir//impl/toolchains/otp:toolchain_type",
    ],
)
