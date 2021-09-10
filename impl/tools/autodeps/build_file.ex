defmodule RulesElixir.Tools.Autodeps.BuildFile do
  @moduledoc """
  Represents a single BUILD file.
  Does not clobber existing BUILD files and arranges load()s at the top.
  Interface is private; intended to be used only with BuildWriter 
  """
  use GenServer
  alias RulesElixir.Tools.Bazel

  defmodule State, do: defstruct [:path, :def_name, loads: [], body: []]

  def init(path) do
    autogen = Path.join(Path.dirname(path), "BUILD.autogenerated.bzl")
    if "BUILD" == Path.basename(path) and File.exists?(autogen) do
      {:ok, %State{path: autogen, def_name: "autogenerated_targets"}}
    else
      {:ok, %State{path: path}}
    end
  end

  def handle_cast({:append, bazel_ast}, state) do
    groups = Enum.group_by(bazel_ast, fn
      %Bazel.Load{} -> :load
      _ -> :other
    end)
    {:noreply, %State{state |
                      loads: state.loads ++ List.wrap(groups[:load]),
                      body: state.body ++ List.wrap(groups[:other])}}
  end

  def handle_call(:flush, _from, state) do
    {path, iodata} = get(state)
    File.write!(path, iodata)
    {:reply, :ok, state}
  end

  def handle_call(:get, _from, state) do
    {:reply, get(state), state}
  end

  defp get(state), do: {state.path, [Bazel.to_iodata(make_ast(state)), "\n"]}

  defp make_ast(state) do
    if state.def_name do
      normalize_loads(state.loads) ++ make_def(state)
    else
      normalize_loads(state.loads) ++ state.body
    end
  end

  defp normalize_loads(loads) do
    Enum.group_by(loads, fn %{from: f} -> f end, fn %{symbols: s} -> s end)
    |> Enum.map(fn {from, sym_groups} ->
      %Bazel.Load{from: from, symbols: Enum.uniq(for g <- sym_groups, s <- g, do: s)}
    end)
  end
  
  defp make_def(state) do
    [%Bazel.Def{name: "do_nothing", body: ["pass"]},
     %Bazel.Def{name: state.def_name,
                params: [{"cont", "do_nothing"}],
                body: fix_native_calls(state.body) ++ [%Bazel.Call{func: "cont", args: []}]}]
  end

  # since we want to "transparently" move the BUILD-file code into a function, we need
  # to fix some names which need to be accessed through `native` module in .bzl files
  defp fix_native_calls(body) do
    Enum.map(body, fn e ->
      case e do
        %Bazel.Rule{rule: r} when r in ["filegroup", "genrule"] ->  %{e | rule: "native." <> r}
        %Bazel.Call{func: f} when f in ["exports_files", "glob"] -> %{e | func: "native." <> f}
        _ -> e
      end
    end)
  end
end
