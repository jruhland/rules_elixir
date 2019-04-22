load("//impl:defs.bzl", "elixir_library", "elixir_script")

def autogenerated_targets():
  elixir_library(
    name = "macros",
    srcs = ["macros.ex"],
    compile_deps = [],
    runtime_deps = [":util"],
    visibility = ["//visibility:public"]
  )
  elixir_library(
    name = "util",
    srcs = ["util.ex"],
    compile_deps = [],
    runtime_deps = [],
    visibility = ["//visibility:public"]
  )
  elixir_library(
    name = "zzz",
    srcs = ["zzz.ex"],
    compile_deps = [":macros"],
    runtime_deps = [":util", "//test/mix/zzz/lib/inner:bleh"],
    visibility = ["//visibility:public"]
  )