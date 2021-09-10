elixir_core_apps = ["elixir", "mix", "iex", "eex", "logger", "ex_unit"]

# Shell snippet to make sure that the right version of OTP is first in $PATH
def add_otp_toolchain_to_path(otpinfo):
    return """
OTP_BIN_DIR="$(cd {otp_bin_dir}; pwd)"
PATH="$OTP_BIN_DIR:$PATH" ;
export PATH ;
    """.format(
        otp_bin_dir = otpinfo.erl.dirname,
    )
