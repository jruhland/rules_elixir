load("@rules_elixir//impl:providers.bzl", "MixLock", "MixProject")

def _mix_lock_impl(ctx):
    return [
        MixLock(
            by_app_name = {
                app_name: label
                for (label, app_name) in ctx.attr.app_for_project.items()
            },
            all_files = depset(
                direct = [ctx.file.lockfile],
                transitive = [d[MixProject].source_files for d in ctx.attr.app_for_project.keys()],
            ),
            lockfile = ctx.file.lockfile,
        ),
    ]

mix_lock = rule(
    _mix_lock_impl,
    attrs = {
        # Do it backwards here since there is no attr.string_keyed_label_dict()
        "app_for_project": attr.label_keyed_string_dict(),
        "lockfile": attr.label(allow_single_file = True),
    },
)

# Construct command line arguments that say where each dep is. Understood by SymlinkTree
def add_mix_deps_to_args(args, mix_deps_provider):
    args.add_all(
        [
            "{}=external/{}/{}".format(dep_app, d.label.workspace_name, d.label.package)
            for (dep_app, d) in mix_deps_provider.by_app_name.items()
        ],
        before_each = "--dep",
    )
