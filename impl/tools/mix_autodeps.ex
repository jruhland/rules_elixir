defmodule Mix.Autodeps.Common do
  # common utils
  def mixfile_path do
    Mix.Project.config_files()
    |> Enum.filter(fn file ->
      Path.basename(file) == "mix.exs"
    end)
    |> case do
	 [mixfile] -> {:ok, mixfile}
	 [] -> {:error, :no_mixfile}
	 mixfiles -> {:error, :too_many_mixfiles, mixfiles}
       end
  end
end

defmodule Mix.Tasks.Autodeps.Inner do
  use Mix.Task

  #alias Mix.Task.Autodeps.Common, as: Common
  @recursive true

  @moduledoc """
  Private recursive task which does the work of actually accumulating dep information.
  """

  @impl true
  def run(args) do
    Mix.Project.get!()

    Mix.Task.run("loadpaths")
    Mix.Task.run("loadconfig")
    project = Mix.Project.config()

    # Phoenix really wants to be loaded at compile time..whatever
    if :phoenix in Keyword.get(project, :deps, []) do
      {:ok, _} = Application.ensure_all_started(:phoenix)
    end

    srcs = project[:elixirc_paths]
    all_paths = MapSet.new(Mix.Utils.extract_files(srcs, [:ex]))

    {:ok, mixfile} = Mix.Autodeps.Common.mixfile_path()
    Process.put(:project_root, Path.dirname(mixfile))
    
    compile_path = Mix.Project.compile_path(project)
    # We need to create this directory and add it to the load path so that
    # `Application.app_dir` works
    File.mkdir_p!(compile_path)
    Code.prepend_path(compile_path)

    Code.compiler_options(ignore_module_conflict: true)
    Kernel.ParallelCompiler.compile(
      Enum.to_list(all_paths),
      each_file: &each_file/2,
      each_module: &each_module/3
    )
  end

  defp each_module(file, module, _bin) do
    root = Process.get(:project_root)
    :ets.insert(:found_deps, {module, root, file})
  end

  defp each_file(file, lexical) do
    {compile, structs, runtime} =
      Kernel.LexicalTracker.remote_references(lexical)

    :ets.insert(:found_deps, {file, compile ++ structs, runtime ++ structs})
  end
end

defmodule Mix.Tasks.Autodeps do
  use Mix.Task
  #alias Mix.Task.Autodeps.Common, as: Common
  @moduledoc """
  Public task that sets things up, calls Autodeps.Inner, and reads the results
  """
  @impl true
  def run(args) do
    Mix.Project.get!()
    :ets.new(:found_deps, [:set, :public, :named_table])
    {:ok, mixfile} = Mix.Autodeps.Common.mixfile_path()
    Process.put(:root_project, Path.dirname(mixfile))

    Mix.Task.run("autodeps.inner")
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
       %{name: Path.rootname(basename),
	 srcs: [basename],
	 compile_deps: dep_targets_from_modules(file, compile_dep_modules),
	 runtime_deps: dep_targets_from_modules(file, runtime_dep_modules)}}
    end)
    |> Enum.group_by(fn {dir, _} -> dir end, fn {_, attrs} -> attrs end)
    |> Enum.map(fn {dir, rule_attrs} ->
      IO.puts("\n")
      IO.puts("#{dir}/BUILD")
      rule_attrs
      |> Enum.sort_by(fn attrs -> attrs.name end)
      |> Enum.map(fn attrs ->
	IO.puts(
  """
  elixir_library(
    name = "#{attrs.name}",
    srcs = #{inspect(attrs.srcs)},
    compile_deps = #{inspect(attrs.compile_deps, pretty: true)},
    runtime_deps = #{inspect(attrs.runtime_deps, pretty: true)},
  )  
  """)
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
    |> Enum.map(&(elem(&1, 1)))
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

