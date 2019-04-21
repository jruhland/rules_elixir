load("//impl:defs.bzl", "elixir_library", "elixir_script")

elixir_library(
    name = "mix_tasks",
    srcs = ["autodeps_recursive.ex", "autodeps.ex"],
    deps = ["//impl/tools/lib:common"],
    visibility = ["//impl/tools:__pkg__"],
)

# elixir_script(
#     name = "read_mix",
#     srcs = ["read_mix.exs"],
#     visibility = ["//impl/tools:__pkg__"],
# )

exports_files(["read_mix.exs"])
