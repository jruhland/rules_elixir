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
  def hello do
    IO.inspect(:mimerl.mime_to_exts("text/plain"), label: "text exts")
    Jason.encode!(%{val: 1, list: [1, 2, 3, 4], version: System.version()})
  end
end
