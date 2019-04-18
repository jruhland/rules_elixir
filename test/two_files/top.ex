require Bottom

defmodule Top do
  def func do
    Bottom.some_macro(fn x -> 4 end)
  end
end

IO.puts("version = #{inspect(System.version)}")
IO.puts("top.func = #{inspect(Top.func())}")
Other.other_func("hi")
IO.puts("argv = #{inspect(System.argv)}")
