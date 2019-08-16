defmodule TestHelperLibraryTest do
  use ExUnit.Case
  doctest TestHelperLibrary

  test "greets the world" do
    assert TestHelperLibrary.hello() == :world
  end
end
