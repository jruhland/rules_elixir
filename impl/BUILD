exports_files(["elixir_script.template", "mix_runner_template.exs", "new_mix_template.exs"])

load(":mix_rules.bzl", "prim_mix_invoke")

prim_mix_invoke(
    name =  "localhex",
    args = ["do", "local.hex", "--force", ",", "local.rebar", "--force"],
    visibility = ["//visibility:public"]
)
