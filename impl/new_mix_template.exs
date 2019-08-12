proj = Path.absname("{project_dir}")
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

File.cd!("{project_dir}", fn ->
  # :os.cmd('find .') |> IO.puts
  Mix.start
  #Mix.debug(true)
  Mix.CLI.main
end)

for {rel, dest} <- outputs do
    File.mkdir_p!(dest)
    for rel_file <- File.ls!("{project_dir}/#{rel}") do
      args = List.flatten ["-rL", "{project_dir}/#{rel}/#{rel_file}", dest] # Linux
      # IO.puts("#{inspect(["cp" | args])}")
      {_, 0} = System.cmd("cp", args)
    end
end
