# Creates the directory structure that Mix expects so that it can start and run properly
# using our compiled code

load("@rules_elixir//impl:providers.bzl", "MixBuild", "MixLock", "MixProject")
load(":mix_lock.bzl", "add_mix_deps_to_args")

def _source_files_copy_impl(ctx):
    build = ctx.attr.mix_build[MixBuild]
    project = build.root_project[MixProject]

    out = ctx.actions.declare_directory("{}/{}".format(
        ctx.label.name,
        ctx.attr.root,
    ))
    args = ctx.actions.args()
    args.add("--output", out.path)
    args.add("--deps-dir", project.deps_path)
    all_the_files = depset(
        transitive = [
            project.source_files,
            project.build_files,
            project.config_files,
        ],
    )
    args.add_all(all_the_files)
    add_mix_deps_to_args(args, build.mix_lock[MixLock])

    ctx.actions.run(
        executable = ctx.executable._subtree_copier,
        inputs = all_the_files,
        outputs = [out],
        arguments = [args],
        # These are literally all source files that we are guaranteed to already have on disk
        execution_requirements = {
            "no-cache": "1",
            "no-remote": "1",
        },
    )
    return [
        DefaultInfo(files = depset([out])),
    ]

source_files_copy = rule(
    _source_files_copy_impl,
    attrs = {
        "mix_build": attr.label(
            mandatory = True,
            providers = [MixBuild],
        ),
        "root": attr.string(
            mandatory = True,
        ),
        "_subtree_copier": attr.label(
            default = Label("@rules_elixir//impl/tools:subtree_copier"),
            executable = True,
            cfg = "host",
        ),
    },
)

def _generated_files_copy_impl(ctx):
    build = ctx.attr.mix_build[MixBuild]
    project = build.root_project[MixProject]
    if project.build_path == "":
        fail("Build path must be set or we will produce a broken docker image")

    bin_root = "{me}/{root}/{build_path}/lib".format(
        me = ctx.label.name,
        root = ctx.attr.root,
        build_path = project.build_path,
    )
    out = ctx.actions.declare_directory(bin_root)
    args = ctx.actions.args()
    args.add("--output", out.path)
    args.add_all(build.archives.values(), before_each = "--ar")

    ctx.actions.run(
        executable = ctx.executable._subtree_copier,
        inputs = build.archives.values(),
        outputs = [out],
        arguments = [args],
        # Do not cache the result of un-archiving as that would defeat the purpose
        execution_requirements = {
            "no-cache": "1",
            "no-remote": "1",
        },
    )
    return [
        DefaultInfo(files = depset([out])),
    ]

generated_files_copy = rule(
    _generated_files_copy_impl,
    attrs = {
        "mix_build": attr.label(
            mandatory = True,
            providers = [MixBuild],
        ),
        "root": attr.string(
            mandatory = True,
        ),
        "_subtree_copier": attr.label(
            default = Label("@rules_elixir//impl/tools:subtree_copier"),
            executable = True,
            cfg = "host",
        ),
    },
)
