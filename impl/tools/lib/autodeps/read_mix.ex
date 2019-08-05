defmodule RulesElixir.Tools.ReadMix do
  alias RulesElixir.Tools.Bazel

  def project_build_file(config, extra_params) do
    cfg = %{deps_path: deps_path} = Enum.into(config, %{})
    cwd = File.cwd!()

    deps =
      Mix.Dep.load_and_cache()
      |> Enum.map(fn %Mix.Dep{app: app, opts: opts} ->
        if opts[:from_umbrella] do
          nil
        else
          case ensure_relative(opts[:dest], cwd) do
            nil ->
              IO.warn(
                "dependency #{app} comes from #{opts[:dest]} which is outside current directory"
              )

            relpath ->
              {app, relpath}
          end
        end
      end)
      |> Enum.filter(&(!is_nil(&1)))
      |> Enum.sort_by(fn {_app, path} ->
        case Path.split(path) do
          [^deps_path | more] -> {1, more}
          other -> {0, other}
        end
      end)

    env_deps = Mix.Dep.load_on_environment(only: Mix.env())
    deps_map = Enum.into(env_deps, %{}, fn d -> {d.app, d} end)

    top_level_deps_according_to_mix = Enum.filter(env_deps, fn d -> d.top_level end)
    top_level_deps = if cfg.app do # not umbrella
      MapSet.new(top_level_deps_according_to_mix)
    else
      top_level_deps_according_to_mix
      |> Enum.flat_map(fn d ->
	d.deps
	|> Enum.filter(fn x ->
	  # I SWEAR that it is supposed to be `:in_umbrella` here
	  !x.opts[:in_umbrella] end)
	|> Enum.map(fn x -> x.app end)
      end)
      |> Enum.into(%MapSet{})
    end

    IO.inspect(top_level_deps, label: "TOP LEVEL DEPS")

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
            deps_names = dep.deps |> Enum.map(fn d -> to_string(d.app) end) |> Enum.sort()

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
               top_level: MapSet.member?(top_level_deps, app)
             }}
        end
      end)
      |> Enum.sort_by(fn {app, _} -> app end)

    %Bazel.Rule{
      rule: "mix_project",
      params:
        [
          name: to_string(cfg.app || Path.basename(cwd)),
          mix_env: to_string(Mix.env()),
          config_path: cfg.config_path,
          build_path: ensure_relative(Mix.Project.build_path(config), cwd),
          apps_path: Map.get(cfg, :apps_path, nil),
          deps_graph: %Bazel.Map{kvs: dep_tree},
          external_projects: %Bazel.Map{kvs: deps}
        ] ++ extra_params
    }
  end

  def transitive_deps(deps_map, app) do
    Stream.concat(
      [app] |> Stream.cycle() |> Enum.take(1),
      deps_map[app].deps |> Stream.flat_map(fn dep -> transitive_deps(deps_map, dep.app) end)
    )
  end

  defp ensure_relative(path, from) do
    case Path.relative_to(path, from) do
      ^path -> nil
      rel -> rel
    end
  end
end
