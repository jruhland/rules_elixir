defmodule Common.CompileTime.Util do
  def blah(env) do
    IO.puts("the env has these keys: #{inspect(Map.keys(env))}")
  end
end
