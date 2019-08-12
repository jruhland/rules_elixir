IO.puts("MIX RUNNER #{inspect(System.argv)}")
outputs = [{outputs_list_body}]
deps =  [{deps_list_body}]

for {root_rel, src} <- deps do
    rel = "{project_dir}/#{root_rel}"
    File.mkdir_p!(rel)
    for rel_file <- File.ls!(src) do
      args = List.flatten ["-rL", "#{src}/#{rel_file}", rel]
      # IO.puts("#{inspect(["cp" | args])}")
      {_, 0} = System.cmd("cp", args)
    end
end

abs_home = Path.absname(System.get_env("HOME"))
System.put_env("HOME", abs_home)
System.put_env("MIX_HOME", abs_home <> "/.mix")

File.cd!("{project_dir}/{subdir}", fn ->
  #:os.cmd('/usr/bin/find .') |> IO.puts
  Mix.start
  #  Mix.debug(true)
  Mix.CLI.main
end)

for {rel, dest} <- outputs do
    File.mkdir_p!(dest)
    case File.ls("{project_dir}/#{rel}") do
      {:ok, entries} -> 
	for rel_file <- entries do
	    args = List.flatten ["-rL", "{project_dir}/#{rel}/#{rel_file}", dest] # Linux
	    # IO.puts("#{inspect(["cp" | args])}")
	    {_, 0} = System.cmd("cp", args)
	end
      _ -> IO.warn("cannot find #{rel}")
    end
end
