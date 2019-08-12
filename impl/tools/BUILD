load("//impl:defs.bzl", "elixir_library", "elixir_script")

elixir_script(
    name = "autodeps",
    srcs = ["autodeps_runner.exs"],
    deps = ["//impl/tools/lib/autodeps:mix_tasks"],
    # env = {"HOME": "test"}
)

# elixir_script(
#     name = "read_mix",
#     srcs = ["//impl/tools/lib/autodeps:read_mix.exs"],
#     deps = ["//impl/tools/lib:common", "//impl/tools/lib:bazel"]
# )


