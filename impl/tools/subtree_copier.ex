defmodule RulesElixir.Tools.SubtreeCopier do
  @moduledoc """
  In order for Mix to correctly boot our docker images, it needs to have everything in the right place.
  Mixfiles, config files, and binaries.   The container rules can preserve some directory structure, but
  only the directory structure within a single target, i.e., NOT including the package.  If two targets
  define an output file of the same name, rules_docker just picks the first one.  So we have this script
  to copy a list of input files to an output directory so that all of the directory structure can be
  propagated correctly.
  """

  @switches [
    # bazel_package: :string,
    output: :string,
    deps_dir: :string,
    dep: :keep, # Parsed by SymlinkTree
    ar: :keep,
  ]

  alias RulesElixir.Tools.{SymlinkTree, Archiver}

  def main(argv) do
    {opts, files} = OptionParser.parse!(argv, strict: @switches)

    deps_links = SymlinkTree.parse_command_line(opts)

    mkdirs = Enum.uniq(for f <- files, do: Path.dirname(f))
    out_base = opts[:output]
    cwd = File.cwd!()

    File.cd!(out_base, fn ->
      for {:ar, archive_path} <- opts do
        Archiver.extract!(File.read!(Path.join(cwd, archive_path)))
      end
    end)

    for md <- mkdirs, do: File.mkdir_p!(Path.join(out_base, md))
    for f <- files do
      from = f
      to = Path.join(out_base, f)
      # IO.puts(:stderr, "From #{from} To #{to}")
      File.cp!(from, to)
      
      :file.change_time(to, {{2000, 5, 11}, {5, 7, 2}})
    end

    deps_dir = opts[:deps_dir]
    if deps_dir, do: File.mkdir_p!(deps_dir)
    for {dirname, real_path} <- deps_links do
      # this is fine, it just means that we don't depend on the dep from the lock
      if File.exists?(real_path) do
        fs = File.cd!(real_path, fn -> Path.wildcard("**", match_dot: true) end)
        # IO.puts(:stderr, "fs = #{inspect(fs)}")
        dout = Path.join([out_base, deps_dir, dirname])
        dirs = MapSet.new(for f <- fs, do: Path.dirname(f))
        for d <- dirs do
          File.mkdir_p!(Path.join(dout, d))
        end
        for f <- fs, !MapSet.member?(dirs, f) do
          from = Path.join(real_path, f)
          to = Path.join(dout, f)
          # IO.puts(:stderr, "#{from}   ->   #{to}")
          File.cp!(from, to)
        end
      end
    end
  end
end
