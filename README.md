# rules_elixir

`rules_elixir` defines Starlark rules for building elixir source code, 
and includes an `autodeps` tool, which automatically generates BUILD files for existing mix projects. 

## Getting Started

### Install Bazel on macOS

See [Installing Bazel on macOS](https://docs.bazel.build/versions/master/install-os-x.html).
```
brew tap bazelbuild/tap
brew install bazelbuild/tap/bazel
```

### First-time Setup
Create a WORKSPACE file e.g.
```
local_repository(
    name = "rules_elixir",
    path = "/Users/russell/src/rules_elixir/",
)

load("@rules_elixir//:deps.bzl", "elixir_rules_dependencies")

elixir_rules_dependencies()
```


Build elixir itself (I don't know why you have to this separately but you do):
```
bazel build @elixir//:elixir_lang
```


Run autodeps tool
```
$ bazel run @rules_elixir//impl/tools:autodeps
```
