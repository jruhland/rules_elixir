load("@rules_elixir//impl:defs.bzl", "elixir_library", "elixir_script", "mix_project")

def autogenerated_targets():
  elixir_library(
    name = "app_one",
    srcs = ["app_one.ex"],
    compile_deps = [":macros"],
    visibility = ["//visibility:public"]
  )
  elixir_library(
    name = "macros",
    srcs = ["macros.ex"],
    compile_deps = [],
    exported_deps = ["//test/mix/umbrella/apps/common/lib:compiletime_util"],
    visibility = ["//visibility:public"]
  )

