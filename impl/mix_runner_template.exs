dest = Path.absname("{out_dir}")
here = File.cwd!()

#0 = System.cmd("cp", ["-r", "{deps_dir}/*", "{project_dir}"]) |> elem(1)
File.cd!("{project_dir}")

Mix.start
# Mix.debug(true)
ret = Mix.CLI.main
File.cd!(here, fn -> {more} end)

# this is a hack in case we didn't produce output
if !File.exists?("{build_path}"), do: :erlang.halt(0)

# !!! TODO
# When you deps.compile non-elixir projects your `ebin` folder can be a link,
# so we need to tell cp to follow links ... but the way to do this is different
# on macOS vs. Linux

args = List.flatten ["-rL", File.ls!(), dest] # Linux
#args = List.flatten ["-r", File.ls!(), dest] # macOS?

0 = System.cmd("cp", args) |> elem(1)
