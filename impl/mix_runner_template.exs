dest = Path.absname("{out_dir}")
here = File.cwd!()

IO.puts("here #{here}")
IO.puts("DEPS_DIR {deps_dir}")
IO.puts("BUILD PATH {build_path}")
IO.puts("PROJET_DIR {project_dir}")
#:os.cmd(to_charlist("find {deps_dir}")) |> IO.puts

File.cd!("{project_dir}")

merged_deps_files = Enum.map(File.ls!("{deps_dir}"), &"{deps_dir}/#{&1}")
File.mkdir_p!("{build_path}")
mcp_args = List.flatten(["-r", merged_deps_files , "{build_path}/"])
IO.inspect(mcp_args, label: "mcp args")
0 = System.cmd("cp", mcp_args) |> elem(1)


IO.puts("MIX RUNNER #{inspect(System.argv())}")
#:os.cmd('find . | sort') |> IO.puts

Mix.start
# Mix.debug(true)
Mix.CLI.main
File.cd!(here, fn -> {more} end)

# this is a hack in case we didn't produce output
if !File.exists?("{build_path}"), do: :erlang.halt(0)

# !!! FIXME
# When you deps.compile non-elixir projects your `ebin` folder can be a link,
# so we need to tell cp to follow links ... but the way to do this is different
# on macOS vs. Linux

#files_to_copy = File.ls!() -- ["bazel-out"]
files_to_copy = ["_build"]

#args = List.flatten ["-rL", File.ls!(), dest] # Linux
args = List.flatten ["-r", files_to_copy, dest] # macOS?

IO.puts("DOING CP (MIX RUNNER), ARGS = #{inspect(args)}")
0 = System.cmd("cp", args) |> elem(1)
