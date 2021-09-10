defmodule RulesElixir.Tools.Archiver do
  @moduledoc """
  Simple archive format which is literally just ETF.
  The reason for doing it this way is becuase :zip and :erl_tar are both non-deterministic (modification times) .
  The reason for archiving at all is to be nicer to the cache server.
  """

  def extract!(archive_bin) do
    for {f, c} <- :erlang.binary_to_term(archive_bin) do
      case c do
        :dir -> File.mkdir_p!(f)
        _cts -> File.write!(f, c)
      end
    end
  end

  def create_from_dir(dir_abs_path) do
    prefix_len = byte_size(Path.dirname(dir_abs_path)) + 1

    entries = for f <- Enum.sort(Path.wildcard("#{dir_abs_path}/**", match_dot: true)) do
      <<_::binary-size(prefix_len), s::binary>> = f
      if File.dir?(f) do
        {s, :dir}
      else
        {s, File.read!(f)}
      end
    end
    :erlang.term_to_binary([{Path.basename(dir_abs_path), :dir} | entries], [:compressed])
  end

end
