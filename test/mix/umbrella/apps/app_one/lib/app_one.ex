defmodule AppOne do
  
  #require Common.Macros
  require AppOne.Macros

  @nothing IO.puts("compiling AppOne")

  def hello do
    answer = Common.add(99, 14)
    IO.puts("app one; answer = #{answer}")
    #v = Common.Macros.my_macro("input")
    v = AppOne.Macros.call_common_function(1, 3)
    IO.puts("v = #{inspect(v)}")
    enc= Jason.encode(Enum.to_list(1..10))
    enc
  end
end
