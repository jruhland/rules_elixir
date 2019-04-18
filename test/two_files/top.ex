require Bottom

defmodule Top do
  def func do
    Bottom.some_macro(4)
  end
end
