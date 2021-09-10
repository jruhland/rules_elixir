# Special rule just for building Elixir itself from source
# Note: not perfectly deterministic

load("//impl:common.bzl", "ElixirLibrary", "elixir_common_attrs")
load(":common.bzl", "add_otp_toolchain_to_path", "elixir_core_apps")

def _build_elixir_impl(ctx):
    outs = {app: ctx.actions.declare_directory("{}/{}".format(ctx.label.name, app)) for app in elixir_core_apps}
    elixir_version = ctx.actions.declare_file("elixir_version")
    otpinfo = ctx.toolchains["@rules_elixir//impl/toolchains/otp:toolchain_type"].otpinfo

    ctx.actions.run_shell(
        inputs = depset(
            direct = [ctx.file._beam_stripper_ex, ctx.file._copy_elixir],
            transitive = [
                otpinfo.files,
                depset(ctx.files.inputs),
            ],
        ),
        progress_message = "Compiling elixir from source",
        outputs = [elixir_version] + outs.values(),
        command = """
set -e ;
export HOME=. ;
export LC_ALL={locale} ;

{setup_otp}

### Create an archive of the elixir sources and unpack it in our execroot.
### The point of this is to avoid problems caused by the `elixir` and `elixirc` shell scripts
### constructing load paths such as "<dir>/bin/../lib/*/ebin" , which do not work properly if `bin` is a symlink
HERE=$PWD
cd {directory} ;
tar -chf "$HERE/elixir.tar" *
cd $HERE
tar -xf "$HERE/elixir.tar"

make compile ;

./bin/elixir -r {copy_elixir_ex} -e 'RulesElixir.Tools.CopyElixirItself.main(System.argv())' -- --output-version {version_file} --prefix {prefix} {apps}
        """.format(
            setup_otp = add_otp_toolchain_to_path(otpinfo),
            directory = repr(ctx.file.any_file_at_root.dirname),
            locale = ctx.attr._elixir_locale,
            beam_stripper_ex = ctx.file._beam_stripper_ex.path,
            paths = repr(["lib/{}/ebin".format(app) for app in elixir_core_apps]),
            copy_elixir_ex = ctx.file._copy_elixir.path,
            prefix = repr(ctx.label.name),
            apps = " ".join(elixir_core_apps),
            version_file = repr(elixir_version.path),
        ),
        env = {
            "PATH": "/bin:/usr/bin:/usr/local/bin",
        },
    )
    libs = depset(outs.values())
    elixir_lib = ElixirLibrary(lib_dirs = libs)
    return [
        DefaultInfo(files = libs),
        elixir_lib,
        platform_common.ToolchainInfo(
            elixirinfo = elixir_lib,
        ),
    ]

_build_elixir_attrs = {
    "inputs": attr.label_list(allow_files = True),
    "any_file_at_root": attr.label(
        allow_single_file = True,
        doc = "The point of this is to do .dirname on it to find our directory",
    ),
    "_copy_elixir": attr.label(
        allow_single_file = True,
        default = Label("@rules_elixir//impl/tools:copy_elixir_itself.ex"),
    ),
    "_beam_stripper_ex": attr.label(
        allow_single_file = True,
        default = Label("@rules_elixir//impl/tools:beam_stripper.ex"),
    ),
}

build_elixir = rule(
    implementation = _build_elixir_impl,
    attrs = dict(_build_elixir_attrs.items() + elixir_common_attrs.items()),
    toolchains = ["@rules_elixir//impl/toolchains/otp:toolchain_type"],
)
