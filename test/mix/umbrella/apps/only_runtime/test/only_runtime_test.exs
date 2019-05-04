defmodule OnlyRuntimeTest do
  use ExUnit.Case
  doctest OnlyRuntime

  test "greets the world" do
    assert OnlyRuntime.hello() == :world
  end
end
