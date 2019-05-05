defmodule Mix.Tasks.Autodeps.Recursive do
  use Mix.Task
  alias RulesElixir.Tools.{Common, Bazel, ReadMix}

  @recursive true
  @moduledoc """
  Recursive helper task which does the work of actually finding dependency information.
  Note that this task cannot be called directly as it depends on the main autodeps task
  to set some things up beforehand.
  """

  @impl true
  def run(opts) do

    Mix.Project.get!()

    Mix.Task.run("loadpaths")
    Mix.Task.run("loadconfig")
    project = Mix.Project.config()

    IO.puts("RECURSIVE #{inspect(project[:app])} #{inspect opts}")
    Process.put(:this_app, project[:app])
    # Phoenix really wants to be loaded at compile time..whatever
    case :code.lib_dir(:phoenix) do
      {:error, :bad_name} -> nil
      lib when is_list(lib) -> Application.ensure_all_started(:phoenix)
    end

    all_paths =
      project[:elixirc_paths]
      |> Mix.Utils.extract_files([:ex])
      |> MapSet.new

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

    # project
    # |> ReadMix.project_build_file(all_paths)
    # |> Bazel.to_iodata
    # |> Common.output_file("BUILD", Keyword.put(opts, :overwrite, true))

  end

  defp each_module(file, module, _bin) do
    :ets.insert(:module_location, {module, file})
    :ets.insert(:file_to_app, {file, Process.get(:this_app)})
    if not Enum.empty?(module.__info__(:macros)) do
      :ets.insert(:file_info, {file, true})
    end
  end

  defp each_file(file, lexical) do
    out = {compile, structs, runtime} = Kernel.LexicalTracker.remote_references(lexical)
    #IO.inspect({file, %{compile: compile, structs: structs, runtime: runtime}})
    :ets.insert(:found_deps, {file, structs ++ compile, structs ++ runtime})
  end
end
