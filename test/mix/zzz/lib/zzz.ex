require ZZZMacros

defmodule Zzz do
  @moduledoc """
  Documentation for Zzz.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Zzz.hello()
      :world

  """
  def hello do
    Bleh.bleh
    IO.inspect(Util.tostring(ZZZMacros.some_macro({1, 2, 3, 4})))
  end
end
