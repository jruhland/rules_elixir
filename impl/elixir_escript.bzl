# Rule for packaging elixir_libraries as `escript` executables

load(":common.bzl", "ElixirLibrary", "elixir_common_attrs")
load(":elixir_rules.bzl", "elixir_library")

def _elixir_escript_impl(ctx):
    print(ctx.attr.deps)

    lib_dirs = depset(
        transitive = [d[ElixirLibrary].lib_dirs for d in ctx.attr.deps],
    )
    escript = ctx.actions.declare_file(ctx.label.name)

    args = ctx.actions.args()
    args.add("--out", escript.path)
    args.add("--main", ctx.attr.main)
    args.add_all(ctx.attr.include_system_apps, before_each = "--include-system-app")
    args.add("--erl-flags", ctx.attr.erl_flags)
    args.add_all(lib_dirs, expand_directories = False)

    ctx.actions.run(
        executable = ctx.executable._escript_builder,
        arguments = [args],
        outputs = [escript],
        inputs = lib_dirs,
        env = {
            "HOME": ".",
            "PATH": "/bin:/usr/bin:/usr/local/bin",
        },
    )

    return [
        DefaultInfo(
            executable = escript,
        ),
    ]

_elixir_escript_attrs = {
    "deps": attr.label_list(
        default = [],
        providers = [ElixirLibrary],
        doc = "Libraries/applications to package in this escript",
    ),
    "main": attr.string(),
    "include_system_apps": attr.string_list(
        default = [],
        doc = "Additional applications from the standard library to bundle in the escript",
    ),
    "erl_flags": attr.string(
        default = "",
        doc = "Additional command line string to pass to the erlang VM",
    ),
    "_escript_builder": attr.label(
        default = Label("@rules_elixir//impl/tools:escript_builder"),
        executable = True,
        cfg = "host",
    ),
}

elixir_escript_rule = rule(
    _elixir_escript_impl,
    attrs = dict(elixir_common_attrs.items() + _elixir_escript_attrs.items()),
    executable = True,
)

def elixir_escript(name = None, srcs = [], deps = [], main = None, **kwargs):
    lib = name + "_lib"
    elixir_library(
        name = lib,
        srcs = srcs,
        compile_deps = deps,
    )

    elixir_escript_rule(
        name = name,
        deps = [lib],
        main = main,
        visibility = ["//visibility:public"],
        **kwargs
    )
