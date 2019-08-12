defmodule RulesElixir.Tools.ReadMix do
  alias RulesElixir.Tools.Bazel

  #PUBLIC API
  def project_build_file(config) do
    cfg = Enum.into(config, %{})
    cwd = File.cwd!()

    env_deps = Mix.Dep.load_on_environment(env: Mix.env())
    deps_map = Enum.into(env_deps, %{}, fn d -> {d.app, d} end)

    dep_tree =
      deps_map
      |> Enum.map(fn {app, dep} ->
        dest = dep.opts[:dest]
        app_name = to_string(app)
        rel_path = ensure_relative(dest, cwd)

        cond do
          app_name != Path.basename(dest) ->
            IO.warn("dependency #{app} is not in a directory of the same name")

          is_nil(rel_path) ->
            IO.warn("dependency #{app} comes from outside current directory")

          true ->
            deps_names = dep.deps
	    #|> Enum.filter(fn d -> Map.has_key?(deps_map, d.app) end)
	    |> Enum.filter(fn d -> !d.opts[:only] or Mix.env() == d.opts[:only] end)
	    |> Enum.map(fn d -> to_string(d.app) end)
	    |> Enum.sort()

            {app_name,
             %{
               path: rel_path,
               deps: deps_names,
               inputs:
                 transitive_deps(deps_map, app)
                 |> Stream.uniq()
                 |> Stream.map(&to_string/1)
                 |> Enum.sort(),
               in_umbrella: !!dep.opts[:from_umbrella],  # supposed to be `:from_umbrella` here 
	       manager: dep.manager,
             }}
        end
      end)
      |> Enum.sort_by(fn {app, _} -> app end)

    project_name = to_string(cfg.app || Path.basename(cwd))
    mix_env = to_string(Mix.env())
    %Bazel.Rule{
      rule: "mix_project",
      params:
        [
          name: project_name <> "_" <> mix_env,
          mix_env: mix_env,
          config_path: cfg.config_path,
          build_path: ensure_relative(Mix.Project.build_path(config), cwd),
          apps_path: Map.get(cfg, :apps_path, nil),
          deps_graph: %Bazel.Map{kvs: dep_tree},
        ]
    }
  end

  def transitive_deps(deps_map, app) do
    case Map.fetch(deps_map, app) do
      {:ok, entry} ->
        Stream.concat(
          [app],
          entry.deps
          |> Stream.flat_map(fn dep ->
            transitive_deps(deps_map, dep.app)
          end)
        )
      _ -> []
    end
  end

  defp ensure_relative(path, from) do
    case Path.relative_to(path, from) do
      ^path -> nil
      rel -> rel
    end
  end
end
