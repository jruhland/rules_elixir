defmodule RulesElixir.Tools.ReadMix do
  alias RulesElixir.Tools.{Bazel, Common}

  @load_mix_rules """
  load("@rules_elixir//impl:defs.bzl", "mix_project")
  """

  def project_build_file(config, targets_by_app) do
    cfg = %{deps_path: deps_path} = Enum.into(config, %{})
    cwd = File.cwd!()

    apps = in_umbrella_deps(config)

    deps =
      Mix.Dep.load_and_cache
      |> Enum.map(fn %Mix.Dep{app: app, scm: scm, opts: opts} ->
        if opts[:from_umbrella] do
          nil
        else
          case ensure_relative(opts[:dest], File.cwd!) do
            nil -> IO.warn("dependency #{app} comes from #{opts[:dest]} which is outside current directory")
            relpath -> {app, relpath}
          end
        end
      end)
      |> Enum.filter(&!is_nil(&1))
      |> Enum.sort_by(fn {app, path} ->
        case Path.split(path) do
          [^deps_path | more] -> {1, more}
          other -> {0, other}
        end
      end)

    %Bazel.Rule{
      rule: "mix_project",
      params: [
        name: to_string(cfg.app || Path.basename(cwd)),
        mix_env: to_string(Mix.env),
        config_path: cfg.config_path,
        external_projects: %Bazel.Map{kvs: deps},
        apps_targets: %Bazel.Map{kvs: Enum.map(targets_by_app, fn
                                  {app, targets} -> {String.to_atom(app), targets}
                                  end)},
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
  
  defp in_umbrella_deps(config) do
    case Mix.Project.apps_paths(config) do
      nil -> MapSet.new
      paths -> MapSet.new(Map.keys(paths))
    end
  end

end

