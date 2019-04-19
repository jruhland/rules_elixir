# 100% cargo culted
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

def elixir_rules_dependencies():
    _maybe(
        git_repository,
        name = "bazel_skylib",
        remote = "https://github.com/bazelbuild/bazel-skylib",
        commit = "3721d32c14d3639ff94320c780a60a6e658fb033",
    )

def _maybe(rule, name, **kwargs):
    """Declares an external repository if it hasn't been declared already."""
    if name not in native.existing_rules():
        rule(name = name, **kwargs)
