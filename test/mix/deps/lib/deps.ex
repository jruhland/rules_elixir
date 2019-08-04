defmodule Deps do
  @moduledoc """
  Documentation for Deps.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Deps.hello()
      :world

  """
  use Timex
  def hello do
    IO.inspect(:mimerl.mime_to_exts("text/plain"), label: "text exts")
    IO.inspect(Timex.now(), label: "Timex.now")
    IO.inspect(%Weather{temp_lo: 30})
    Jason.encode!(%{val: 1, list: [1, 2, 3, 4], version: System.version()})
  end
end
