IO.puts("APP TWO TEST")

defmodule AppTwoTest do
  use ExUnit.Case

  test "does the right action" do
    #assert 1 == 0
    assert :mock = AppTwo.run_action
  end
end
