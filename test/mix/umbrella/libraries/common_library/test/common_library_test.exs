defmodule CommonLibraryTest do
  use ExUnit.Case
  doctest CommonLibrary

  test "greets the world" do
    assert CommonLibrary.hello() == :world
  end
end
