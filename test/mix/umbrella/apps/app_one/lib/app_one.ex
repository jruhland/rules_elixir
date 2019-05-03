defmodule AppOne do
  
  require Common.Macros

  @nothing IO.puts("compiling AppOne")

  def hello do
    answer = Common.add(99, 14)
    IO.puts("app one; answer = #{answer}")
    v = Common.Macros.my_macro("input")
    IO.puts("v = #{inspect(v)}")
  end
end
