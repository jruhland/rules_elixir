load("//impl:elixir_rules.bzl", "elixir_iex", "elixir_script_test")

def _expand_template_impl(ctx):
    template_file = ctx.file.template_file
    if not template_file:
        template_file = ctx.actions.declare_file(ctx.label.name + ".template")
        ctx.actions.write(
            output = template_file,
            content = ctx.attr.template_content,
        )

    out = ctx.actions.declare_file(ctx.attr.filename)
    ctx.actions.expand_template(
        template = template_file,
        output = out,
        substitutions = ctx.attr.substitutions,
    )
    return [
        DefaultInfo(files = depset([out])),
    ]

expand_template_rule = rule(
    implementation = _expand_template_impl,
    attrs = {
        "template_file": attr.label(allow_single_file = True),
        "template_content": attr.string(),
        "filename": attr.string(),
        "substitutions": attr.string_dict(default = {}),
    },
)

def mix_test(name = None, mix_env = "test", deps = [], data = [], env = {}, test_kwargs = {}):
    attrs = {
        "deps": deps + ["@rules_elixir//impl/tools:hex"],
        "data": data + native.glob(["test/**", "integration_tests/**", "priv/**", "samples/**", "fixture/**"]),
        "env": dict({"MIX_ENV": mix_env, "HOME": "."}.items() + env.items()),
    }

    test_helper = name + "_test_helper"
    expand_template_rule(
        name = test_helper,
        template_file = "@rules_elixir//impl/tools:bazel_test_helper.exs",
        filename = "bazel_test_helper.exs",
        substitutions = {
            "%%subdir%%": native.package_name(),
        },
    )

    elixir_script_test(
        name = name,
        srcs = [
            "@rules_elixir//impl/tools:load_env_file.exs",
            test_helper,
        ],
        tags = ["mix_test"],
        # flaky = True,
        **dict(attrs.items() + test_kwargs.items())
    )

    config_loader = name + "iex_config_loader"
    expand_template_rule(
        name = config_loader,
        template_content = """
File.cd!("%%subdir%%")
Mix.start
Code.compile_file "mix.exs"
Mix.Task.run("loadconfig")
spawn_link(fn -> {:ok, _} = :application.ensure_all_started(Mix.Project.config()[:app]) end)
File.cd!(Path.join(System.get_env("BUILD_WORKSPACE_DIRECTORY"), "%%subdir%%"))
        """,
        substitutions = {
            "%%subdir%%": native.package_name(),
        },
        filename = "config_loader.exs",
    )

    elixir_iex(
        name = name + "_iex",
        srcs = [
            "@rules_elixir//impl/tools:load_env_file.exs",
            config_loader,
        ],
        **attrs
    )
