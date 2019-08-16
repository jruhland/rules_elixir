defmodule CommonTest do
  use ExUnit.Case
  doctest Common

  require Common.Macros

  test "greets the world" do
    assert Common.add(2, 3) == 5
    assert Common.Macros.my_macro(4) == {:macro_returned, 4}
  end
end
