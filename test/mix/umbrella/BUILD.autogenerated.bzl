load("@rules_elixir//impl:defs.bzl", "mix_project")

def autogenerated_targets(overrides = {}):
  mix_project(
    name = "umbrella",
    mix_env = "dev",
    config_path = "config/config.exs",
    deps_path = "deps",
    deps_names = ["jason", "mimerl"],
    apps_targets = {
                     "app_one": ["//test/mix/umbrella/apps/app_one/lib:app_one",
                                 "//test/mix/umbrella/apps/app_one/lib:macros"],
                     "app_two": ["//test/mix/umbrella/apps/app_two/lib:app_two",
                                 "//test/mix/umbrella/apps/app_two/lib:some_module"],
                     "common": ["//test/mix/umbrella/apps/common/lib:common",
                                "//test/mix/umbrella/apps/common/lib:compiletime_util",
                                "//test/mix/umbrella/apps/common/lib:macros"],
                     "only_runtime": ["//test/mix/umbrella/apps/only_runtime/lib:only_runtime"]
                   },
    apps_path = "apps",
    build_path = "_build/dev"
  )

