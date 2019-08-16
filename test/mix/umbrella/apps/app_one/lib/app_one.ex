defmodule AppOne do
  
  #require Common.Macros
  require AppOne.Macros

  @nothing IO.inspect(Application.get_all_env(:app_one), label: "app one compile-time config")

  @compile_time_json Jason.encode(%{ok: "cool"})

  def hello do
    IO.puts("hello4")
    answer = Common.add(99, 14)
    IO.puts("app one; answer = #{answer}")
    IO.inspect(@compile_time_json, label: "compile time json encode")
    v = AppOne.Macros.call_common_function(1, 3)
    IO.puts("v = #{inspect(v)}")
    enc = Jason.encode(Enum.to_list(1..10))
    IO.inspect(CommonLibrary.hello, label: "common library says")
    IO.inspect(%ExampleSchema{}, label: "example ecto schema")
    enc
  end
end
