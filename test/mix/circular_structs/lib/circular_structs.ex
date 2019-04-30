defmodule CircularStructs do
  @moduledoc """
  Documentation for CircularStructs.
  """

  @doc """
  Hello world.

  ## Examples

      iex> CircularStructs.hello()
      :world

  """
  def hello do
    a = %StructA{}
    b = %StructB{}
    IO.inspect([a, b])
  end
end
