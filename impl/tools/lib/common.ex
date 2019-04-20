defmodule RulesElixir.Tools.Common do
  alias Inspect.Algebra, as: A

  @width 80

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

  def format_rule(rule, params, opts \\ %Inspect.Opts{}) do
    A.format(rule_to_doc(rule, params, opts), @width)
  end
  
  defp rule_to_doc(rule, params, opts) do
    A.container_doc("#{rule}(", params, ")", opts,
      fn {attr, value}, opts ->
	A.space(
	  to_string(attr),
	  A.space(
	    "=",
	    A.nest(A.to_doc(value, opts), :cursor)))
      end,
      break: :strict)
  end
end
