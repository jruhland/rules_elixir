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
  @unused IO.inspect(:application.get_all_env(:app_two), label: "app two compile-time config")
  def hello do
    answer = Common.add(43, 14)
    IO.puts("app two; answer = #{answer}")
    IO.puts("my other module says hi: #{SomeModule.some_function}")
    IO.puts("runtime only says: #{inspect(OnlyRuntime.hello)}")
    {"text extensions", :mimerl.mime_to_exts("text/plain")}
  end
end
