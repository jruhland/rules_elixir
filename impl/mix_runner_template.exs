dest = Path.absname("{out_dir}")
here = File.cwd!()
IO.puts("STARTED @ #{here}")
#:os.cmd('find .') |> IO.puts
IO.puts("deps_dir {deps_dir}")
IO.puts("project_dir {project_dir}")
:os.cmd(to_charlist("ls {deps_dir}")) |> IO.puts
# 0 = System.cmd("cp", ["-r", "{deps_dir}/*", "{project_dir}"]) |> elem(1)
File.cd!("{project_dir}")
IO.puts("CHANGED TO {project_dir}")
#:os.cmd('find .') |> IO.puts

Mix.start
Mix.CLI.main
File.cd!(here, fn -> {more} end)
# this is a hack in case we didn't produce output
if !File.exists?("{build_path}"), do: :erlang.halt(0)
File.cd!("{build_path}")
#args = List.flatten ["-rL", File.ls!(), dest]
args = List.flatten ["-r", File.ls!(), dest]
0 = System.cmd("cp", args) |> elem(1)
