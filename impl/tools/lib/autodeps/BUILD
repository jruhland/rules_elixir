load("//impl:defs.bzl", "elixir_library", "elixir_script")

elixir_library(
    name = "mix_tasks",
    srcs = ["autodeps_recursive.ex", "autodeps.ex"],
    deps = ["//impl/tools/lib:common"],
    visibility = ["//impl/tools:__pkg__"],
)
