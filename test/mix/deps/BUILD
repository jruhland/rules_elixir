load("@rules_elixir//impl:defs.bzl", "mix_project")

mix_project(
  name = "deps",
  mix_env = "dev",
  elixirc_paths = ["lib"],
  config_path = "config/config.exs",
  deps_path = "deps",
  deps_names = ["jason", "mimerl"],
  build_path = "_build/dev"
)

