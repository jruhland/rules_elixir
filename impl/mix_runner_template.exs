dest = Path.absname("{out_dir}")
here = File.cwd!()
#IO.puts("DEPS_DIR {deps_dir}")
IO.puts("find {deps_dir}")
:os.cmd('find {deps_dir}') |> IO.puts

#0 = System.cmd("cp", ["-r", "{deps_dir}/*", "{project_dir}"]) |> elem(1)
File.cd!("{project_dir}")
# IO.puts("CHANGED TO {project_dir}")
# IO.puts("find .")
# :os.cmd('find .') |> IO.puts

IO.puts("running mix #{inspect(System.argv)}")

Mix.start
Mix.debug(true)
ret = Mix.CLI.main
File.cd!(here, fn -> {more} end)
IO.puts("ret = #{inspect(ret)}")
# this is a hack in case we didn't produce output
if !File.exists?("{build_path}"), do: :erlang.halt(0)

# IO.puts("find . again")
# :os.cmd('find . | xargs file') |> IO.puts
# File.cd!("{build_path}")

# !!! TODO
# When you deps.compile non-elixir projects your `ebin` folder can be a link,
# so we need to tell cp to follow links ... but the way to do this is different
# on macOS vs. Linux

args = List.flatten ["-rL", File.ls!(), dest] # Linux
#args = List.flatten ["-rL", File.ls!(), dest] # macOS?

# IO.puts("find {build_path}")
# :os.cmd('find .') |> IO.puts
# IO.puts("find #{dest}")
# :os.cmd(to_charlist("find #{dest}")) |> IO.puts

IO.puts("CP #{inspect(args)}")
0 = System.cmd("cp", args) |> elem(1)

# IO.puts("FIND #{dest}")
# :os.cmd(to_charlist("find #{dest}")) |> IO.puts
