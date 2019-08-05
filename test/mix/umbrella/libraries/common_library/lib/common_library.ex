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
    [:version, 4, :hello, :from, :external, :common, :library, "without compiling third-party deps?"]
  end

  def macro_helper do
    "I am helping this macro"
  end
end
