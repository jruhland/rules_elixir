defmodule AppTwo do
  @moduledoc """
  Documentation for AppTwo.
  """

  @doc """
  Hello world.

  ## Examples

      iex> AppTwo.hello()
      :world

  """
  def hello do
    answer = Common.add(43, 14)
    IO.puts("app two; answer = #{answer}")
    IO.puts("my other module says hi: #{SomeModule.some_function}")
  end
end
