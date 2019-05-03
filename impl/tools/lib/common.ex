defmodule RulesElixir.Tools.Common do

  def active_mixfile do
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

  def sibling_target(file) do
    ":" <> Path.rootname(Path.basename(file))
  end

  def qualified_target(file) do
    path_to_target(Path.relative_to(Path.absname(file), workspace_root()))
  end

  def workspace_root do
    System.get_env("BUILD_WORKSPACE_DIRECTORY")
  end

  def output_file(contents, filename, opts) do
    write? = Keyword.get(opts, :overwrite, false) or not File.exists?(filename)
    if not Keyword.get(opts, :dry_run, false) do
      if write?, do: File.write!(filename, contents)
    end
    if write? and Keyword.get(opts, :echo, false) do
      IO.puts(["### ", filename, ":\n", contents, "\n"])
    end
  end

  defp path_to_target(file) do
    dir = Path.dirname(file)
    file = Path.rootname(Path.basename(file))

    "//" <> Enum.join(Path.split(dir), "/") <> ":" <> file
  end

end
