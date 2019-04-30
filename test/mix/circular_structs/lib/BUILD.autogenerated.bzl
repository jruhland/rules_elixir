load("@rules_elixir//impl:defs.bzl", "elixir_library", "elixir_script")

def autogenerated_targets():
  v = {"hi": True, "hello": True}
  elixir_library(
    name = "circular_structs",
    srcs = ["circular_structs.ex"],
    compile_deps = [":struct_a", ":struct_b"],
    runtime_deps = [":struct_a", ":struct_b"],
    visibility = ["//visibility:public"]
  )
  elixir_library(
    name = "struct_a",
    srcs = ["struct_a.ex"],
    compile_deps = [],
    runtime_deps = [],
    visibility = ["//visibility:public"]
  )
  elixir_library(
    name = "struct_b",
    srcs = ["struct_b.ex"],
    compile_deps = [":struct_a"],
    runtime_deps = [],
    visibility = ["//visibility:public"]
  )