load("//impl:defs.bzl", "elixir_library", "elixir_script")

elixir_library(
    name = "mix_tasks",
    srcs = ["autodeps_recursive.ex", "autodeps.ex"],
    compile_deps = ["//impl/tools/lib:bazel"],
    runtime_deps = ["//impl/tools/lib:bazel", "//impl/tools/lib:common"],
    visibility = ["//impl/tools:__pkg__"],
)

exports_files(["read_mix.exs"])
