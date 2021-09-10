load("@rules_elixir//impl/toolchains/elixir:find_elixir.bzl", "find_elixir")

find_elixir(name = "find_elixir")

# define the same toolchain aliased under two different names, `local` (the default) and the actual version.
# this is becuase trying to put two values of the same constraint setting on one toolchain is an error.

toolchain(
    name = "host_elixir_toolchain",
    target_compatible_with = [
        "@rules_elixir//impl/toolchains/elixir:local",
    ],
    toolchain = "find_elixir",
    toolchain_type = "@rules_elixir//impl/toolchains/elixir:toolchain_type",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "host_elixir_toolchain_versioned",
    target_compatible_with = [
        "@rules_elixir//impl/toolchains/elixir:%%version%%",
    ],
    toolchain = "find_elixir",
    toolchain_type = "@rules_elixir//impl/toolchains/elixir:toolchain_type",
    visibility = ["//visibility:public"],
)
