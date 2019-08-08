dest = Path.absname("{out_dir}")
here = File.cwd!()

#0 = System.cmd("cp", ["-r", "{deps_dir}/*", "{project_dir}"]) |> elem(1)
File.cd!("{project_dir}")

IO.puts("MIX RUNNER #{inspect(System.argv())}")
#:os.cmd('find .') |> IO.puts

Mix.start
# Mix.debug(true)
Mix.CLI.main
File.cd!(here, fn -> {more} end)

# this is a hack in case we didn't produce output
if !File.exists?("{build_path}"), do: :erlang.halt(0)

# !!! TODO
# When you deps.compile non-elixir projects your `ebin` folder can be a link,
# so we need to tell cp to follow links ... but the way to do this is different
# on macOS vs. Linux

#files_to_copy = File.ls!() -- ["bazel-out"]
files_to_copy = ["_build"]

#args = List.flatten ["-rL", File.ls!(), dest] # Linux
args = List.flatten ["-r", files_to_copy, dest] # macOS?

IO.puts("DOING CP (MIX RUNNER), ARGS = #{inspect(args)}")
0 = System.cmd("cp", args) |> elem(1)
