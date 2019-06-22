defmodule CommonLibrary do
  @moduledoc """
  Documentation for CommonLibrary.
  """

  @doc """
  Hello world.

  ## Examples

      iex> CommonLibrary.hello()
      :world

  """
  def hello do
    [:hello, :from, :common, :library, "without compiling third-party deps?"]
  end
end
