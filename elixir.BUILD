_elixir_build_cmd = """
    set -e
    GEN_ROOT=`pwd`
    #cd external/elixir/elixir-1.8.1/
    #cd external/elixir/elixir-1.9-dev/
    cd external/elixir/{elixir_version}
    ELIXIR_ROOT=`pwd`
    make compile
    cd $$GEN_ROOT
    mkdir $(OUTS)
    # create directory structure that the elixir binaries expect
    cp $$ELIXIR_ROOT/bin/* $(location bin)
    cd $(location lib)
    for app in `ls $$ELIXIR_ROOT/lib`; do
      mkdir $$app
      cp -r $$ELIXIR_ROOT/lib/$$app/ebin $$app
    done
"""

genrule(
    name = "elixir_lang",
    srcs = glob(include = ["Makefile", "lib/**"],
                exclude = [
                    "lib/**/* */**",  # paths with spaces
                    "lib/**/ebin/**", # existing binaries
                ],
                exclude_directories = 1),
    message = "Building elixir from source...",
    cmd = _elixir_build_cmd.format(elixir_version = "elixir-1.9-dev"),
    outs = ["bin", "lib"]
)

#e.g. `elixir_tool elixir ...` to run elixir, `elixir_tool mix` to run mix, etc
sh_binary(
    name = "elixir_tool",
    deps = ["@bazel_tools//tools/bash/runfiles"],
    data = [":elixir_lang"],
    srcs = ["@rules_elixir//:elixir_runfiles.bash"],
    visibility = ["//visibility:public"],
)

# we RUN `elixir_tool` when compiling, but scripts DEPEND ON `elixir_tool` 
# and bazel gives us a warning if we depend on an sh_binary -- so make an 
# identical sh_library to avoid it 
sh_library(
    name = "elixir_tool_lib",
    deps = ["@bazel_tools//tools/bash/runfiles"],
    data = [":elixir_lang"],
    srcs = ["@rules_elixir//:elixir_runfiles.bash"],
    visibility = ["//visibility:public"],
)

