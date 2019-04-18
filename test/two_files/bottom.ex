defmodule Bottom do
  defmacro some_macro(x) do
    quote do
      {:macro_returned, unquote(Macro.escape(x))}
    end
  end
end
