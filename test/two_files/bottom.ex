defmodule Bottom do
  @system_version System.version
  defmacro some_macro(x) do
    quote do
      {:macro_returned44, unquote(@system_version), unquote(Macro.escape(x))}
    end
  end
end
