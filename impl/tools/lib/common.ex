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
end
