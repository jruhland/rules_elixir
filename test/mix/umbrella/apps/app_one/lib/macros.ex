defmodule AppOne.Macros do
  defmacro call_common_function(x, y) do
    Common.CompileTime.Util.blah(__ENV__)
    quote do
      Common.add(unquote(x), unquote(y))
    end
  end
end
