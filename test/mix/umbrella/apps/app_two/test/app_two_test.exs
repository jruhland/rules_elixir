defmodule AppTwoTest do
  use ExUnit.Case

  test "does the right action" do
    assert :mock = AppTwo.run_action
  end
  
end
