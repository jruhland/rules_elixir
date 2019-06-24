load("@rules_elixir//impl:defs.bzl", "elixir_script", "elixir_test")

elixir_test(
    name = "do_test",
    srcs = ["test_helper.exs", "app_two_test.exs"],
    deps = ["//test/mix/umbrella:all"],
    env = {"MIX_ENV": "test"},
)
