defmodule RulesElixir.Tools.Autodeps.Labeler do
  @moduledoc "Knows how to construct labels from paths"
  use GenServer
  alias RulesElixir.Tools.Bazel
  
  # Public API
  def start_link(opts),       do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def fully_qualified(path),  do: GenServer.call(__MODULE__, {:fq, path}, :infinity)
  def at_root(name),          do: GenServer.call(__MODULE__, {:at_root, name}, :infinity)
  def relative_to_root(nil),  do: nil
  def relative_to_root(path), do: GenServer.call(__MODULE__, {:rel_root, path}, :infinity)

  # Implementation
  def handle_call({:fq, path}, _from, state) do
    {:reply, Bazel.Label.fully_qualified(state.name, state.root, path), state}
  end
  def handle_call({:at_root, name}, _from, state) do
    {:reply, "@#{state.name}//:#{name}", state}
  end
  def handle_call({:rel_root, path}, _from, state) do
    {:reply, Path.relative_to(Path.expand(path), state.root), state}
  end

  def init(opts) do
    with(
      {:ok, root} <- find_ws_root(opts),
      {:ok, name} <- find_ws_name(opts)
    ) do
      {:ok, %{root: root, name: name}}
    end
  end

  defp find_ws_root(opts) do
    root = System.get_env("BUILD_WORKSPACE_DIRECTORY") || opts[:workspace_root]
    if is_nil(root) do
      {:error, "--workspace-root is required when not running with `bazel run`"}
    else
      {:ok, Path.absname(root)}
    end
  end
  defp find_ws_name(opts) do
    name = opts[:workspace_name]
    if is_nil(name), do: {:error, "--workspace-name is required"}, else: {:ok, name}
  end
end
