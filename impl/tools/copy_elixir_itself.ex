defmodule RulesElixir.Tools.CopyElixirItself do
  @moduledoc """
  Find where the currently-running elixir binaries are, and copy them into specified output directories.
  """

  @switches [
    output_version: :string,
    prefix: :string,
  ]

  def main(argv) do
    {opts, apps} = OptionParser.parse!(argv, strict: @switches)
    go(opts[:output_version], opts[:prefix], apps)
  end

  # For A in apps; create a directory "$(dirname $output_version)/$prefix/$A" and copy A's ebin, priv, etc dirs into it
  def go(output_version, prefix, apps) do
    File.write!(output_version, System.version())
    output_dir = Path.dirname(output_version)
    for a <- apps do
      out = Path.join(output_dir, "#{prefix}/#{a}")
      lib_dir = :code.lib_dir(String.to_atom(a))
      for f <- File.ls!(lib_dir) do
        src = Path.join(lib_dir, f)
        # When copying from source-built elixir, we don't need to copy the mix.exs files that live here
        if File.dir?(src) do
          of = Path.join(out, f)
          File.mkdir_p!(of)
          File.cp_r!(src, of)
        end
      end
    end
  end
end
