defmodule MockAction do
  def exec do
    IO.puts("this is where the missiles would be fired")
    :mock
  end
end
