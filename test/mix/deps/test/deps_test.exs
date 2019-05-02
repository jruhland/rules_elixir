defmodule DepsTest do
  use ExUnit.Case
  doctest Deps

  test "greets the world" do
    assert Deps.hello() == :world
  end
end
