defmodule AppOneTest do
  use ExUnit.Case
  doctest AppOne

  test "calls the helper" do
    assert "I am helping this test" == TestHelperLibrary.test_helper_function()
  end
end
