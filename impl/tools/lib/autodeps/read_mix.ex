defmodule RulesElixir.Tools.ReadMix do
  alias RulesElixir.Tools.{Bazel, Common}

  @load_mix_rules """
  load("@rules_elixir//impl:defs.bzl", "mix_project")
  """

  def project_build_file(config, compiled_files) do
    cfg = Enum.into(config, %{})
    cwd = File.cwd!()

    apps = in_umbrella_deps(config)

    third_party_deps =
      config
      |> all_deps_names
      |> MapSet.difference(apps)
      |> Enum.map(&to_string/1)

    %Bazel.Rule{
      rule: "mix_project",
      params: [
        name: to_string(cfg.app || Path.basename(cwd)),
        mix_env: to_string(Mix.env),
        config_path: cfg.config_path,
        deps_path: cfg.deps_path,
        deps_names: third_party_deps,                   
	#apps_names: [to_string(cfg.app) | Enum.to_list(apps)],
	apps_names: List.wrap(cfg.app) ++ Enum.into(apps, [], &to_string/1),
        lib_targets: Enum.into(compiled_files, [], &Common.qualified_target/1),
        apps_path: Map.get(cfg, :apps_path, nil),
        build_path: ensure_relative(Mix.Project.build_path(config), cwd),
      ]
    }

  end

  defp ensure_relative(path, from) do
    case Path.relative_to(path, from) do
      ^path -> nil
      rel -> rel
    end
  end
  
  defp all_deps_names(config) do
    config |> Mix.Project.deps_paths |> Map.keys |> MapSet.new
  end

  defp in_umbrella_deps(config) do
    case Mix.Project.apps_paths(config) do
      nil -> MapSet.new
      paths -> MapSet.new(Map.keys(paths))
    end
  end

end

