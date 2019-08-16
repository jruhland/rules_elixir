load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")


# def elixir_rules_dependencies():
#     http_archive(
#         name = "elixir",
#         # urls = ["https://github.com/elixir-lang/elixir/archive/v1.8.1.tar.gz"],
#         # sha256 = "de8c636ea999392496ccd9a204ccccbc8cb7f417d948fd12692cda2bd02d9822",

#         urls = ["https://github.com/fazzone/elixir/archive/1.9-dev.tar.gz"],
#         sha256 = "fc946bb482e1cb1e7cb1f04f82191cc5cb58baff6c061f507b01f4b5023a1156",
#         build_file = "@rules_elixir//:elixir.BUILD",
#     )
load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
def elixir_rules_dependencies():

    new_git_repository(
        name = "elixir",
        remote = "https://github.com/elixir-lang/elixir.git",
        commit = "511a51ba8925daa025d3c2fd410e170c1b651013", # v1.8.1
        #commit = "333ebbe13b81a250765cb2174bb9158f64d1a10d", # random 1.9 dev commit
        #commit = "459319fb751f81399b6e3826789782452ea5c3c9",
        build_file = "@rules_elixir//:elixir.BUILD",
    )
    
    # new_git_repository(
    #     name = "elixir",
    #     remote = "/elixir",
    #     commit = "f6b5fa311d430d30b33078be8cefbf5777976ca4",
    #     build_file = "@rules_elixir//:elixir.BUILD",
    # )

