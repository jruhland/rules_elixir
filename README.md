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
Create a WORKSPACE file
Build elixir itself:
```
bazel build @elixir//:elixir_lang
```
