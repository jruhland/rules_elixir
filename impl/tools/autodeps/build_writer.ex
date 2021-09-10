defmodule RulesElixir.Tools.Autodeps.BuildWriter do
  @moduledoc """
  Maintains the registry of path -> BuildFile process
  """
  use GenServer
  alias RulesElixir.Tools.Autodeps.BuildFile
  # Public API 
  def start_link(_),           do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  # Absolute path required to avoid aliasing.
  def emit(path, body),        do: GenServer.cast(__MODULE__, {:emit, path, body})
  def flush(),                 do: GenServer.call(__MODULE__, :flush, :infinity)
  def get(),                   do: GenServer.call(__MODULE__, :get, :infinity)

  # Implementation
  
  def init(_), do: {:ok, %{}}

  def handle_cast({:emit, path, body}, state), do: emit(path, {:append, body}, state)

  def handle_call(:flush, _from, state) do
    Stream.run(call_each_stream(:flush, state))
    {:reply, :ok, state}
  end

  def handle_call(:get, _from, state) do
    {:reply, Enum.to_list(call_each_stream(:get, state)), state}
  end

  defp call_each_stream(call, state) do
    Map.values(state)
    |> Task.async_stream(fn pid -> GenServer.call(pid, call) end, ordered: false)
  end

  defp emit(path, cast, state) do
    case state do
      %{^path => pid} -> 
        GenServer.cast(pid, cast)
        {:noreply, state}
      _ ->          
        {:ok, pid} = GenServer.start_link(BuildFile, path)
        GenServer.cast(pid, cast)
        {:noreply, Map.put(state, path, pid)}
    end
  end
end
