IO.inspect(System.argv, label: "mix runner script args")
IO.inspect(System.get_env(), label: "mix runner script env")

dest = Path.absname("{out_dir}")
here = File.cwd!()
File.cd!("{project_dir}")
Mix.start
Mix.CLI.main
File.cd!(here, fn -> {more} end)
# this is a hack in case we didn't produce output
if !File.exists?("{build_path}"), do: :erlang.halt(0)
File.cd!("{build_path}")
args = List.flatten ["-rL", File.ls!(), dest]
0 = System.cmd("cp", args) |> elem(1)
