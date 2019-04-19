defmodule ZzzTest do
  use ExUnit.Case
  doctest Zzz

  test "greets the world" do
    assert Zzz.hello() == :world
  end
end
