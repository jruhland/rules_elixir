load("@rules_elixir//impl:defs.bzl", "mix_project")

mix_project(
  name = "deps",
  mix_env = "dev",
  config_path = "config/config.exs",
  deps_path = "deps",
  deps_names = ["jason", "mimerl"],
  lib_targets = ["//test/mix/deps/lib:deps"],
  build_path = "_build/dev"
)

