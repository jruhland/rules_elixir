defmodule Common.Macros do
  defmacro my_macro(x) do
    quote do
      {:macro_returned, unquote(x)}
    end
  end
end
