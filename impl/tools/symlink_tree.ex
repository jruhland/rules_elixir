defmodule RulesElixir.Tools.SymlinkTree do
  @moduledoc """
  Helper to create the directory structure that Mix expects during builds.
  It is convenient for us to have things like deps and binaries in all sorts of
  different places; this lets us make it appear as normal to Mix.
  
  The only problem is when things get written to the potentially-shared dep directory,
  for that reason we have the copy_instead_of_linking option, to avoid unrelated actions
  from polluting each other's cache by trashing a shared dependency directory
  """
  def make_symlink_tree(root, links, opts \\ []) do
    File.mkdir_p!(root)
    File.cd!(root, fn ->
      copy_instead = List.wrap(opts[:copy_instead_of_linking])
      for {dir_name, real_path} <- links do
        if dir_name in copy_instead do
          # We require GNU cp
          which_cp =
            case :os.type() do
              {:unix, :darwin} -> System.find_executable("gcp") || raise "GNU coreutils required!"
              _ -> System.find_executable("cp") || raise "No cp?"
            end

          cpcmd = ["-rL", real_path, dir_name]
          {"", 0} = System.cmd(which_cp, cpcmd)
        else
          File.ln_s(real_path, dir_name)
        end
      end
    end)
  end

  # Parse a `dep: :keep` switch into a map like `make_symlink_tree` wants
  def parse_command_line(opts) do
    for {:dep, name_and_dir} <- opts do
      [dir_name, rel_path] = String.split(name_and_dir, "=", parts: 2)
      {dir_name, Path.absname(rel_path)}
    end
    |> Map.new
  end

end
