load("//impl:def.bzl", "elixir_library")

elixir_library(
    name = "bottom",
    srcs = ["bottom.ex"]
)
elixir_library(
    name = "top",
    srcs = ["top.ex"],
    deps = [":bottom"]
)
