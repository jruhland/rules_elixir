# Rule which exposes `elixir` from your PATH as a elixir toolchain.
# This is the default elixir toolchain unless you specify another platform (see this pkg BUILD)

load(":common.bzl", "add_otp_toolchain_to_path", "elixir_core_apps")
load("//impl:common.bzl", "ElixirLibrary", "elixir_common_attrs")

def _find_elixir_impl(ctx):
    outs = {app: ctx.actions.declare_directory("{}/{}".format(ctx.label.name, app)) for app in elixir_core_apps}
    elixir_version = ctx.actions.declare_file("elixir_version")
    otpinfo = ctx.toolchains["@rules_elixir//impl/toolchains/otp:toolchain_type"].otpinfo
    ctx.actions.run_shell(
        inputs = depset(direct = [ctx.file._copy_elixir], transitive = [otpinfo.files]),
        outputs = [elixir_version] + outs.values(),
        command = """
set -e ;
export HOME=. ;
export LC_ALL={locale} ;

{setup_otp}

elixir -r {copy_elixir_ex} -e 'RulesElixir.Tools.CopyElixirItself.main(System.argv())' -- --output-version {version_file} --prefix {prefix} {apps}
        """.format(
            locale = ctx.attr._elixir_locale,
            setup_otp = add_otp_toolchain_to_path(otpinfo),
            copy_elixir_ex = ctx.file._copy_elixir.path,
            prefix = repr(ctx.label.name),
            apps = " ".join(elixir_core_apps),
            version_file = repr(elixir_version.path),
        ),
        use_default_shell_env = True,
        # This rule literally copies elixir from the system PATH; it should not be cached or run remotely
        execution_requirements = {
            "no-cache": "1",
            "no-remote": "1",
        },
    )
    libs = depset(outs.values())
    elixir_lib = ElixirLibrary(lib_dirs = libs)
    return [
        DefaultInfo(
            files = libs,
            runfiles = ctx.runfiles(outs.values()),
        ),
        elixir_lib,
        platform_common.ToolchainInfo(
            elixirinfo = elixir_lib,
        ),
    ]

find_elixir = rule(
    implementation = _find_elixir_impl,
    attrs = dict({
        "_copy_elixir": attr.label(
            allow_single_file = True,
            default = Label("@rules_elixir//impl/tools:copy_elixir_itself.ex"),
        ),
    }.items() + elixir_common_attrs.items()),
    toolchains = ["@rules_elixir//impl/toolchains/otp:toolchain_type"],
)
