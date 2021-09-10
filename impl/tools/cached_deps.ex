defmodule RulesElixir.Tools.CachedDeps do
  @moduledoc """
  We want to cache the structure returned by Mix.Dep.cached()
  However it includes tons of absolute paths which will be different across bazel actions
  So we need to save a "relocatable" version...
  """

  alias RulesElixir.Tools.SymlinkTree

  @switches [
    subdir: :string,
    mix_env: :string,
    dep: :keep, # Parsed by SymlinkTree
    output: :string
  ]

  def main(argv) do
    {opts, _args} = OptionParser.parse!(argv, strict: @switches)
    deps_links = SymlinkTree.parse_command_line(opts)
    top_cwd = File.cwd!()
    output_file = Path.absname(opts[:output])
    File.cd!(opts[:subdir])

    Mix.start()
    Mix.env(String.to_atom(opts[:mix_env]))
    Code.compile_file("mix.exs")

    SymlinkTree.make_symlink_tree(Mix.Project.config()[:deps_path], deps_links)

    Mix.Dep.load_and_cache()

    rda = relocatable_deps_cache(top_cwd)
    File.write!(output_file, :erlang.term_to_binary(rda))
  end

  @marker "%%prefix%%"

  def replace_prefix!(s, pre, rep) do
    if !String.starts_with?(s, pre) do
      raise "#{inspect(s)} does not start with #{inspect(pre)}"
    else
      String.replace_prefix(s, pre, rep)
    end
  end

  def make_relocatable(d = %Mix.Dep{}, root_dir, build_path) do
    %{d |
      from: String.replace_prefix(d.from, root_dir, @marker),
      opts: (for {k, v} <- d.opts do
                 case k do
                   :dest -> {k, replace_prefix!(v, root_dir, @marker)}
                   :build -> {k, replace_prefix!(v, build_path, @marker)}
                   _ -> {k, v}
                 end
             end),
      deps: (for subdep <- d.deps, do: make_relocatable(subdep, root_dir, build_path))}
  end

  def relocate(d = %Mix.Dep{}, root_dir, build_path) do
    %{d |
      from: String.replace_prefix(d.from, @marker, root_dir),
      opts: (for {k, v} <- d.opts do
                 case k do
                   :dest -> {k, replace_prefix!(v, @marker, root_dir)}
                   :build -> {k, replace_prefix!(v, @marker, build_path)}
                   _ -> {k, v}
                 end
             end),
      deps: (for subdep <- d.deps, do: relocate(subdep, root_dir, build_path))}
  end

  def rehydrate({k, ds}, rel_to) do
    build_path = Mix.Project.build_path()
    {k, (for d <- ds, do: relocate(d, rel_to, build_path))}
  end

  def relocatable_deps_cache(rel_to) do
    {k, ds} =
      if function_exported?(Mix.ProjectStack, :read_cache, 1) do
        Mix.ProjectStack.read_cache({:cached_deps, Mix.Project.get!()})
      else
        Mix.State.read_cache({:cached_deps, Mix.Project.get!()})
      end
    build_path = Mix.Project.build_path()
    {k, (for d <- ds, do: make_relocatable(d, rel_to, build_path))}
  end

end
