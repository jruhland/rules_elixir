defmodule RulesElixir.Tools.Bazel do
  @moduledoc """
  Pretty printer for Bazel BUILD files
  """
  alias Inspect.Algebra, as: A

  @width 80

  defmodule Rule, do: defstruct [:rule, :params]
  defmodule Def,  do: defstruct [:name, {:params, []}, :body]
  defmodule Root, do: defstruct [:body]

  def to_iodata(body, opts \\ %Inspect.Opts{limit: :infinity}) do
    A.format(bazel_doc(%Root{body: body}, opts), @width)
  end

  defp bazel_doc(e, opts) do
    case e do
      %Rule{} -> rule_doc(e.rule, e.params, opts)
      %Def{}  -> def_doc(e.name, e.params, e.body, opts)
      %Root{} -> root_doc(e.body, opts)
      m when is_map(m) -> map_doc(m, opts)
      b when is_binary(b) -> b
      e -> A.to_doc(e, opts)
    end
  end

  defp root_doc(body, opts) do
    body
    |> Enum.map(fn e -> bazel_doc(e, opts) end)
    |> Enum.intersperse(A.line())
    |> A.concat
  end

  defp rule_doc(rule, params, opts) do
    has_value = Enum.filter(params, fn {_attr, value} -> !is_nil(value) end)
    A.container_doc("#{rule}(", has_value, ")", opts,
      fn {attr, value}, opts ->
	value_doc =
	  case value do
	    # make sure to quote strings here
	    b when is_binary(b) -> A.to_doc(b, opts)
	    _ -> bazel_doc(value, opts)
	  end

        A.space(
          to_string(attr),
          A.space("=", A.nest(value_doc, :cursor))
	)
      end,
      break: :strict)
  end

  defp map_doc(m, opts) do
    A.container_doc("{", Enum.to_list(m), "}", opts,
      fn {k, v}, opts ->
	A.space(
	  A.concat(A.to_doc(k, opts), ":"),
	  A.nest(bazel_doc(v, opts), :cursor))
      end)
  end

  defp def_doc(name, params, body, opts) do
    prototype = A.container_doc("def #{name}(", params, "):", opts, fn i, _opts -> to_string(i) end)
    A.concat([
      prototype,
      A.line(),
      "  ",
      body
      |> case do
           [] -> ["pass"]
           _ -> body
         end
      |> Enum.map(fn e -> bazel_doc(e, opts) end)
      |> Enum.intersperse(A.line())
      |> A.concat
      |> A.nest(:cursor)
    ])
  end
end
