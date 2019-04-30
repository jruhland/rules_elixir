defmodule ReadMix do
  alias RulesElixir.Tools.{Bazel}

  @load_mix_rules """
  load("@rules_elixir//impl:defs.bzl", "mix_project")
  """

  def run(config) do
    cfg = Enum.into(config, %{})
    cwd = File.cwd!()
    all_deps_names = config |> Mix.Project.deps_paths |> Map.keys |> MapSet.new
    apps_names = config |> Mix.Project.apps_paths |> Map.keys |> MapSet.new
    third_party_deps = all_deps_names |> MapSet.difference(apps_names) |> Enum.map(&to_string/1)
    iodata = Bazel.to_iodata(
      [@load_mix_rules,
       %Bazel.Rule{rule: "mix_project",
                   params: [name: to_string(cfg.app || Path.basename(cwd)),
	                    elixirc_paths: cfg.elixirc_paths,
	                    config_path: cfg.config_path,
	                    deps_path: cfg.deps_path,
                            deps_names: third_party_deps,
	                    apps_path: cfg.apps_path,
                            build_path: Path.relative_to(Mix.Project.build_path(config), cwd)]},
       "\n"])
    File.write!("BUILD", iodata)
  end
  
end

File.cd!(System.get_env("BUILD_WORKING_DIRECTORY"))

Application.ensure_all_started(:mix)
# todo fix this lol
Mix.Task.run("local.hex", ["--force"])

Code.compile_file("mix.exs")

IO.inspect(Mix.Project.config)
IO.inspect(Path.basename(File.cwd!()))
IO.puts("================================================================")
ReadMix.run(Mix.Project.config)


