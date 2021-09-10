# Repository rules to consume source dependencies from Hex or Git, via Mix.

load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("@bazel_tools//tools/build_defs/repo:git_worker.bzl", "git_repo")

##### hex_package rule #####
# Re-usable core of the hex_package repository rule
def _do_hex_package(ctx, attrs):
    name_with_version = "{}-{}".format(attrs.package, attrs.version)
    filename = "{}.tar".format(name_with_version)
    args = {
        "url": [
            "https://repo.hex.pm/tarballs/{}".format(filename),
        ],
        "output": filename,
    }

    if attrs.bazel_sha256 != None:
        args["sha256"] = attrs.bazel_sha256
    else:
        print("No SHA!", attrs)

    ctx.report_progress("Fetching Hex package {}".format(attrs.package))
    ctx.download(**args)

    extract_path = ctx.path(attrs.directory)
    ctx.extract(archive = filename, output = extract_path)
    ctx.delete(filename)
    ctx.delete(extract_path.get_child("VERSION"))
    ctx.delete(extract_path.get_child("CHECKSUM"))
    ctx.extract(archive = extract_path.get_child("contents.tar.gz"), output = extract_path)
    ctx.delete(extract_path.get_child("contents.tar.gz"))

    # Generate a fake Hex manifest file.
    # Newer Hex generates this manifest file as binary ETF but still supports reading an
    # "old-style" text format.  This file is required by Mix otherwise deps check fails
    gen_manifest = "{pkg},{version},{sha},{repo}".format(
        pkg = attrs.package,
        version = attrs.version,
        sha = attrs.sha,
        repo = attrs.repo,
    )
    ctx.file(extract_path.get_child(".hex"), gen_manifest)

    gen_build_file = """
load("@rules_elixir//impl:mix_rules.bzl", "mix_external_project")
load("@rules_elixir//impl:elixir_rules.bzl", "elixir_library")
mix_external_project(
    app = "{app}",
    name = "prod",
    source_files = glob(["**"]),
    directory = "{directory}",
)
filegroup(
  name = "lib",
  srcs = glob(["lib/**/*.ex"]),
  visibility = ["//visibility:public"],
)
elixir_library(
  name = "elixir_simple_library",
  srcs = [":lib"],
  visibility = ["//visibility:public"],
)
    """.format(
        app = attrs.app,
        directory = attrs.directory,
        name_with_version = name_with_version,
        filename = filename,
        version = attrs.version,
        sha = attrs.sha,
        repo = attrs.repo,
        #        deps = attrs.deps,
    )
    ctx.file(extract_path.get_child("BUILD"), gen_build_file)

def _hex_package_impl(ctx):
    _do_hex_package(ctx, ctx.attr)

_hex_package_attrs = {
    "app": attr.string(),
    "package": attr.string(mandatory = True),
    "version": attr.string(mandatory = True),
    "sha": attr.string(mandatory = True),
    "bazel_sha256": attr.string(),
    "repo": attr.string(default = "hexpm"),
    "deps": attr.string_list(),
    "lock": attr.string_dict(),
    "directory": attr.string(default = "."),
}

hex_package = repository_rule(
    implementation = _hex_package_impl,
    attrs = _hex_package_attrs,
)

##### mix_git_repository rule #####

def _execute_or_fail(ctx, command, **kwargs):
    result = ctx.execute(command, **kwargs)
    if result.return_code != 0:
        fail("[{me}] error in command `{cmd}` - {stderr}".format(
            me = ctx.name,
            cmd = " ".join(command),
            stderr = result.stderr,
        ))
    return result

# Re-usable core of simple_git_repo rule
def _do_simple_git_repo(ctx, attrs):
    ctx.delete(attrs.directory)
    ctx.report_progress("Cloning Git repo {}".format(attrs.remote))
    _execute_or_fail(ctx, ["git", "clone", attrs.remote, attrs.directory])
    _execute_or_fail(ctx, ["git", "checkout", attrs.commit], working_directory = attrs.directory)
    revparse = _execute_or_fail(ctx, ["git", "rev-parse", "HEAD"], working_directory = attrs.directory)
    if revparse.stdout.strip() != attrs.commit:
        fail("Did not check out the right commmit, got {} when {} was requested".format(
            revparse.stdout.strip(),
            attrs.commit,
        ))

    # delete the git dir but make it so `git rev-parse HEAD` can still work
    # also keep the config which stores list of remotes
    # (both are required or mix deps check will fail)
    git_dir = ctx.path(attrs.directory).get_child(".git")
    git_config = ctx.read(git_dir.get_child("config"))

    ctx.delete(git_dir)
    ctx.file(git_dir.get_child("HEAD"), attrs.commit)
    ctx.file(git_dir.get_child("config"), git_config)

    # git refuses to work without these directories but doesn't look very hard at them
    ctx.file(git_dir.get_child("refs").get_child(".keep"), git_config)
    ctx.file(git_dir.get_child("objects").get_child(".keep"), git_config)

def _simple_git_repo_impl(ctx):
    _do_simple_git_repo(ctx, ctx.attr)

simple_git_repo_attrs = {
    "app": attr.string(),
    "remote": attr.string(),
    "commit": attr.string(),
    "directory": attr.string(default = "."),
}

simple_git_repo = repository_rule(
    _simple_git_repo_impl,
    attrs = simple_git_repo_attrs,
)

# Re-usable core of mix_git_repository rule
def _do_mix_git_repository(ctx, attrs):
    gen_build_file = """
load("@rules_elixir//impl:mix_rules.bzl", "mix_external_project")
load("@rules_elixir//impl:elixir_rules.bzl", "elixir_library")
mix_external_project(
    app = "{app}",
    name = "prod",
    source_files = glob(["**"]),
)
filegroup(
  name = "lib",
  srcs = glob(["lib/**/*.ex"]),
  visibility = ["//visibility:public"],
)
elixir_library(
  name = "elixir_simple_library",
  srcs = [":lib"],
  visibility = ["//visibility:public"],
)
    """.format(
        app = attrs.app,
    )
    _do_simple_git_repo(ctx, attrs)
    ctx.file(ctx.path(attrs.directory).get_child("BUILD"), gen_build_file)

def _mix_git_repository_impl(ctx):
    _do_mix_git_repository(ctx, ctx.attr)

mix_git_repository = repository_rule(
    _mix_git_repository_impl,
    attrs = dict(simple_git_repo_attrs.items() + {
        "app": attr.string(),
        "deps": attr.label_list(),
    }.items()),
)
