load("//impl:defs.bzl", "elixir_library", "elixir_script")

elixir_library(
    name = "bottom",
    srcs = ["bottom.ex"]
)

elixir_library(
    name = "other",
    srcs = ["other.ex"]
)

elixir_script(
    name = "top",
    srcs = ["top.ex"],
    deps = [":bottom", ":other"]
)
