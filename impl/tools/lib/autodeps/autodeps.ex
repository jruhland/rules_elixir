defmodule Mix.Tasks.Autodeps do
  use Mix.Task
  alias RulesElixir.Tools.Common

  @moduledoc """
  Generate BUILD files for the mix project in the current directory
  """
  @impl true
  def run(args) do
    Mix.Project.get!()
    :ets.new(:found_deps, [:set, :public, :named_table])
    {:ok, mixfile} = Common.active_mixfile()
    Process.put(:root_project, Path.dirname(mixfile))

    Mix.Task.run("autodeps.recursive")
    read_deps()
  end

  defp read_deps do
    root = Process.get(:root_project)
    # use 2 ets tables to avoid filter?
    :ets.match(:found_deps, :"$1")
    |> Enum.filter(fn [{file, _, _}] -> is_binary(file) end)
    |> Enum.map(fn [{file, compile_dep_modules, runtime_dep_modules}] ->
      build_dir = Path.dirname(Path.relative_to(file, root))
      basename = Path.basename(file)
      {build_dir, 
       [name: Path.rootname(basename),
	srcs: [basename],
	compile_deps: dep_targets_from_modules(file, compile_dep_modules),
	runtime_deps: dep_targets_from_modules(file, runtime_dep_modules)]}
    end)
    |> Enum.group_by(fn {dir, _} -> dir end, fn {_, attrs} -> attrs end)
    |> Enum.map(fn {dir, rule_attrs} ->
      IO.puts("\n")
      IO.puts("#{dir}/BUILD")

      rule_attrs
      |> Enum.sort_by(fn attrs -> Keyword.get(attrs, :name) end)
      |> Enum.map(fn attrs ->
	IO.puts(Common.format_rule("elixir_library", attrs))
      end)
    end)
  end

  defp dep_targets_from_modules(file, modules) do
    modules
    |> Enum.flat_map(fn module ->
      case :ets.lookup(:found_deps, module) do
	[{_, _project, dep_file}] when file != dep_file -> [dep_file]
        _ -> []
      end
    end)
    |> Enum.uniq
    |> Enum.map(fn dep_file ->
      if Path.dirname(file) == Path.dirname(dep_file) do
	# sort sibling deps first
	{0, sibling_target(file)}
      else
	{1, qualified_target(dep_file)}
      end
    end)
    |> Enum.sort
    |> Enum.map(fn {_sort, target} -> target end)
  end

  defp sibling_target(file) do
    ":" <> Path.rootname(Path.basename(file))
  end

  defp qualified_target(file) do
    path_to_target(Path.relative_to(file, Process.get(:root_project)))
  end

  defp path_to_target(file) do
    dir = Path.dirname(file)
    file = Path.rootname(Path.basename(file))

    "//" <> Enum.join(Path.split(dir), "/") <> ":" <> file
  end
end

