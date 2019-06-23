defmodule RulesElixir.Tools.ReadMix do
  alias RulesElixir.Tools.Bazel

  def project_build_file(config, extra_params) do
    cfg = %{deps_path: deps_path} = Enum.into(config, %{})
    cwd = File.cwd!()

    deps =
      Mix.Dep.load_and_cache
      |> Enum.map(fn %Mix.Dep{app: app, opts: opts} ->
        if opts[:from_umbrella] do
          nil
        else
          case ensure_relative(opts[:dest], cwd) do
            nil -> IO.warn("dependency #{app} comes from #{opts[:dest]} which is outside current directory")
            relpath -> {app, relpath}
          end
        end
      end)
      |> Enum.filter(&!is_nil(&1))
      |> Enum.sort_by(fn {_app, path} ->
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
        build_path: ensure_relative(Mix.Project.build_path(config), cwd),
        apps_path: Map.get(cfg, :apps_path, nil),
        external_projects: %Bazel.Map{kvs: deps},
      ] ++ extra_params
    }

  end

  defp ensure_relative(path, from) do
    case Path.relative_to(path, from) do
      ^path -> nil
      rel -> rel
    end
  end
  
end

