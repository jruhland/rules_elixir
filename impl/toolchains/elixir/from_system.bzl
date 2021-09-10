load("@rules_elixir//impl/toolchains/elixir:elixir_version.bzl", "elixir_versions")

# Returns the version string of a working local elixir installation, or None
def get_installed_elixir_version(ctx):
    which_elixir = ctx.which("elixir")

    # No elixir installed
    if which_elixir == None:
        return None

    # Ask for the installed version
    version_result = ctx.execute([which_elixir, "-e", "IO.write System.version"])
    if version_result.return_code != 0:
        print("Could not determine elixir version: " + version_result.stderr)
        return None

    # The version must be something that we know about
    if version_result.stdout not in elixir_versions:
        print("Unknown elixir version \"{}\"".format(version_result.stdout))
        return None
    return version_result.stdout

def _elixir_from_system_path_impl(ctx):
    working_elixir_install = get_installed_elixir_version(ctx)
    if None == working_elixir_install:
        # Try to fail gracefully if we can't use the existing elixir install for any reason
        ctx.file("BUILD", "")
    else:
        ctx.template(
            "BUILD",
            ctx.path(ctx.attr._build_file),
            {
                "%%version%%": working_elixir_install,
            },
        )

elixir_from_system_path = repository_rule(
    _elixir_from_system_path_impl,
    attrs = {
        "_build_file": attr.label(
            default = Label("@rules_elixir//impl/toolchains/elixir:from_system.BUILD"),
        ),
    },
)
