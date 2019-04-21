workspace(name = "rules_elixir")

load("@rules_elixir//:deps.bzl", "elixir_rules_dependencies")

elixir_rules_dependencies()

# new_local_repository(
#     name = "elixir",
#     path = "c:/Users/rmcq/Desktop/elixir/elixir/",
#     build_file = "elixir.BUILD"
# )

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
http_archive(
    name = "elixir",
    # urls = ["https://github.com/elixir-lang/elixir/archive/v1.8.1.tar.gz"],
    # sha256 = "de8c636ea999392496ccd9a204ccccbc8cb7f417d948fd12692cda2bd02d9822",
    urls = ["https://github.com/fazzone/elixir/archive/1.9-dev.tar.gz"],
    build_file = "@//:elixir.BUILD"
)

# load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")

# new_git_repository(
#     name = "elixir",
#     remote = "https://github.com/elixir-lang/elixir.git",
#     commit = "459319fb751f81399b6e3826789782452ea5c3c9",
#     build_file = "@//:elixir.BUILD",
# )
