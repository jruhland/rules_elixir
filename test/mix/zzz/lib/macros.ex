defmodule ZZZMacros do
  defmacro some_macro(x) do
    quote do
      %{thing: Util.tostring(unquote(x)),
	string: unquote(Util.tostring(x))}
    end
  end
end
