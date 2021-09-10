defmodule RulesElixir.Tools.Bazel do
  @moduledoc """
  Pretty printer for Bazel BUILD files
  """
  alias Inspect.Algebra, as: A

  @width 103

  ### public api

  defmodule Rule,  do: defstruct [:rule, :params]
  defmodule Def,   do: defstruct [:name, {:params, []}, :body]
  defmodule Root,  do: defstruct [:body]
  defmodule Map,   do: defstruct [:kvs] # like a map but ordered
  defmodule Infix, do: defstruct [:op, :left, :right]
  defmodule Call,  do: defstruct [:func, :args]
  defmodule Load,  do: defstruct [:from, :symbols]
  defmodule DepsList, do: defstruct [:elems] # like a list but with linebreaks
  defmodule ConfigSetting, do: defstruct [:name, :define_values]

  def to_iodata(body, opts \\ %Inspect.Opts{limit: :infinity}) do
    A.format(bazel_doc(%Root{body: body}, opts), @width)
  end

  defmodule Label do
    @moduledoc "Helpers for constructing bazel labels. Absolute paths required"
    
    def fully_qualified(workspace_name, workspace_root, file) do
      Path.expand(file)
      |> Path.relative_to(workspace_root)
      |> path_to_target(workspace_name)
    end

    def in_workspace(workspace_root, file) do
      Path.expand(file)
      |> Path.relative_to(workspace_root)
      |> path_to_target()
    end

    def in_package(file) do
      ":#{file}"
    end

    defp path_to_target(path, wsname \\ nil) do
      dir = Path.dirname(path)
      pkg = if dir == ".", do: "", else: dir
      file = Path.basename(path)

      in_workspace = "//" <> pkg <> ":" <> file
      if wsname do
        "@" <> wsname <> in_workspace
      else
        in_workspace
      end
    end

  end

  ### implementation
  
  defp bazel_doc(e, opts) do
    case e do
      %Rule{}           -> rule_doc(e.rule, e.params, opts)
      %Def{}            -> def_doc(e.name, e.params, e.body, opts)
      %Root{}           -> root_doc(e.body, opts)
      %Map{}            -> map_doc(e.kvs, opts)
      %Infix{}          -> infix_doc(e.op, e.left, e.right, opts)
      %Call{}           -> call_doc(e.func, e.args, opts)
      %ConfigSetting{}  -> configsetting_doc(e.name, e.define_values, opts)
      %Load{}           -> call_doc("load", Enum.map([e.from | e.symbols], &inspect/1), opts)
      %DepsList{}       ->
        A.container_doc("[", e.elems, "]", opts,
          fn e, opts ->
            A.nest(quoted(e, opts), :cursor)
          end)
      %{__struct__: _} = s -> struct_doc(s, opts)
      m when is_map(m) -> map_doc(m, opts)
      b when is_binary(b) -> b
      true -> "True"
      false -> "False"
      a when is_atom(a) -> A.to_doc(to_string(a), opts)
      e -> A.to_doc(e, opts)
    end
  end

  defp root_doc(body, opts) do
    body
    |> Enum.map(fn e -> bazel_doc(e, opts) end)
    |> Enum.intersperse(A.line())
    |> A.concat
  end

  defp remove_keys_with_nil_values(params) do
    Enum.filter(params, fn {_attr, value} -> !is_nil(value) end)
  end

  defp rule_doc(rule, params, opts) do
    A.container_doc("#{rule}(", remove_keys_with_nil_values(params), ")", opts,
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

  defp configsetting_doc(name, define_values, opts) do
    A.container_doc("config_setting(", [name: name, define_values: define_values], ")", opts,
      fn ({:name, value}, opts) ->
        A.space(
          to_string("name"),
          A.space("=", A.to_doc(value, opts))
        )
      ({:define_values, value}, opts) ->
        A.space(
          to_string("define_values"),
          A.space("=", map_doc(value, opts))
        )
      end,
      break: :strict)
  end

  defp quoted(e, opts) do
    cond do
      is_binary(e) -> A.to_doc(e, opts)
      is_boolean(e) -> if e, do: "True", else: "False"
      is_atom(e) -> A.to_doc(to_string(e), opts)
      true -> bazel_doc(e, opts)
    end
  end

  defp map_doc(m, opts) do
    A.container_doc("{", remove_keys_with_nil_values(m), "}", opts,
      fn {k, v}, opts ->
        A.space(
          A.concat(quoted(k, opts), ":"),
          A.nest(quoted(v, opts), :cursor))
      end)
  end

  defp struct_doc(s, opts) do
    m = Elixir.Map.delete(s, :__struct__)
    A.container_doc("struct(", remove_keys_with_nil_values(m), ")", opts,
      fn {f, v}, opts ->
        A.space(
          A.concat(to_string(f), " ="),
          A.nest(quoted(v, opts), :cursor))
      end)
  end

  defp infix_doc(op, left, right, opts) do
    A.space(
      bazel_doc(left, opts),
      A.space(
        op,
        bazel_doc(right, opts)))
  end

  defp call_doc(func, args, opts) do
    A.container_doc("#{func}(", args, ")", opts, &bazel_doc/2)
  end

  defp def_doc(name, params, body, opts) do
    prototype = A.container_doc("def #{name}(", params, "):", opts,
      fn
        {param, default}, opts ->
          A.space(
            to_string(param),
            A.space("=", bazel_doc(default, opts))
          )
        param, _opts -> to_string(param)
      end)
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
