def query_erlang_system_info(r_ctx, erl_exe, atom):
    result = r_ctx.execute([
        erl_exe,
        "-noshell",
        "-eval",
        "io:put_chars(erlang:system_info({}))".format(atom),
        "-s",
        "erlang",
        "halt",
    ])
    if result.return_code != 0:
        print("Failed to query erlang version information: " + result.stderr)
        return None
    return result.stdout

def query_erts_version(r_ctx, erl_exe):
    return query_erlang_system_info(r_ctx, erl_exe, "version")

def query_otp_release(r_ctx, erl_exe):
    return query_erlang_system_info(r_ctx, erl_exe, "otp_release")

def query_otp_version(r_ctx, erl_exe, otp_release):
    cmd = [
        erl_exe,
        "-noshell",
        "-eval",
        """
        io:put_chars(element(2, file:read_file(filename:join([filename:dirname(code:lib_dir()), "releases", "{}", "OTP_VERSION"]))))
        """.format(otp_release),
        "-s",
        "erlang",
        "halt",
    ]
    result = r_ctx.execute(cmd)

    if result.return_code != 0:
        print("Failed to query OTP version information: " + result.stderr)
        return None
    return result.stdout.strip()

def query_erlang_version_info(r_ctx, which_erl):
    otp_release = query_otp_release(r_ctx, which_erl)
    erts_version = query_erts_version(r_ctx, which_erl)
    otp_version = query_otp_version(r_ctx, which_erl, otp_release)
    if not (otp_release and erts_version and otp_version):
        return None
    else:
        return struct(
            which_erl = which_erl,
            otp_release = otp_release,
            erts_version = erts_version,
            otp_version = otp_version,
        )

def query_local_erlang_install(r_ctx):
    which_erl = r_ctx.which("erl")
    if which_erl == None:
        return None
    return query_erlang_version_info(r_ctx, which_erl)

def erts_headers_cc_library(erts_version):
    return """
cc_library(
  name = "erts_headers", 
  hdrs = glob(["*.h"]),
  strip_include_prefix = "/erts-{}/include",
  visibility = ["//visibility:public"]
)
    """.format(erts_version)
