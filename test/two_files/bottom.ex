defmodule Bottom do
  defmacro some_maco(x) do
    quote do
      {:macro_returned, unquote(x)}
    end
  end
end
