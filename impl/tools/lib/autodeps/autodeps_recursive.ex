defmodule Mix.Tasks.Autodeps.Recursive do
  use Mix.Task
  @recursive true
  @moduledoc """
  Recursive helper task which does the work of actually finding dependency information.
  Note that this task cannot be called directly as it depends on the main autodeps task
  to set some things up beforehand.
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

    {:ok, mixfile} = RulesElixir.Tools.Common.active_mixfile()
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
