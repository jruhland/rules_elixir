defmodule RulesElixir.Tools.DepBuilder do
  @moduledoc """
  Sets up a fake environment for Mix and then invokes `mix compile` or `mix deps.compile`.
  """

  @switches [
    subdir: :string,
    # either `compile` or `deps.compile`
    mode: :string,
    output_archive: :string,
    # Specifies how to create the deps/ directory. Each arg should be app=/path/to/app;
    # each dir will be symlinked as deps/app
    dep: :keep, # Parsed by SymlinkTree
    # The same except for dependencies' `ebin` directories 
    lib: :keep,
    # lib archives to be extracted directly into _build/$MIX_ENV/lib
    ar: :keep,

    lockfile: :string,
    mix_deps_cached: :string,
  ]

  alias RulesElixir.Tools.{SymlinkTree, Archiver, CachedDeps}

  def main(argv) do
    Mix.start()
    Mix.shell(Mix.Shell.Quiet)
    # Mix.debug(true)

    {opts, [my_dep_name | _] = deps_names} = OptionParser.parse!(argv, strict: @switches)

    # Bazel gives us relative paths only, we need absolute so they work even if we `cd` away
    System.put_env("MIX_REBAR", Path.expand(System.get_env("MIX_REBAR_RELATIVE")))
    System.put_env("MIX_REBAR3", Path.expand(System.get_env("MIX_REBAR3_RELATIVE")))
    mix_build_path = Path.dirname(Path.expand(System.get_env("MIX_BUILD_PATH_RELATIVE")))
    System.put_env("MIX_BUILD_PATH", mix_build_path)

    extra_build_dirs = 
      for {:lib, libdir} <- opts do
        {Path.basename(libdir), Path.absname(libdir)}
      end

    top_cwd = Path.absname(File.cwd!())

    my_dep = String.to_atom(hd(deps_names))
    deps_links = SymlinkTree.parse_command_line(opts)

    case Keyword.fetch(opts, :subdir) do
      {:ok, subdir} ->
        case File.cd(subdir) do
          {:error, :enoent} ->
            File.mkdir_p!(subdir)
            File.cd!(subdir)
          :ok -> :ok
        end
      _ -> :ok
    end

    Code.compile_file("mix.exs")

    # Set up the deps/build symlink trees where Mix will expect
    SymlinkTree.make_symlink_tree(Mix.Project.config[:deps_path], deps_links, copy_instead_of_linking: [my_dep_name])

    build_lib = Path.join(Mix.Project.build_path(), "lib")
    SymlinkTree.make_symlink_tree(build_lib, extra_build_dirs)

    File.cd!(build_lib, fn ->
      for {:ar, archive_path} <- opts do
        Archiver.extract!(File.read!(Path.join(top_cwd, archive_path)))
      end
    end)

    if opts[:mix_deps_cached] do
      cached_deps_file = Path.join(top_cwd, opts[:mix_deps_cached])
      cached_deps = CachedDeps.rehydrate(:erlang.binary_to_term(File.read!(cached_deps_file)), top_cwd)
      if function_exported?(Mix.ProjectStack, :write_cache, 2) do
        Mix.ProjectStack.write_cache({:cached_deps, Mix.Project.get!()}, cached_deps)
      else
        Mix.State.write_cache({:cached_deps, Mix.Project.get!()}, cached_deps)
      end
    end

    Mix.Task.run("loadconfig")
    fix_fake_git_repos()
    Mix.Task.run("deps")

    build_dir = Path.join(build_lib, my_dep_name)

    case opts[:mode] do
      "compile" ->
        # --force becuase we if we are here we _definitely_ want to compile; might as well say so
        # --no-deps-check because otherwise mix likes to delete our perfectly-good binaries
        # Relevant in elixir1.8, see https://github.com/elixir-lang/elixir/blob/v1.8/lib/mix/lib/mix/tasks/deps.compile.ex#L111 
        Mix.Task.run("compile", ["--force", "--no-deps-check"])
        Mix.Task.run("compile.app", [])
        # TODO: patch the manifests to be deterministic; we can't delete them becuase Mix will try to compile at startup
      "deps.compile" ->
        case for dep = %{app: ^my_dep} <- Mix.Dep.cached(), do: dep do
            [the_dep] -> 
              Mix.Tasks.Deps.Compile.compile([the_dep])
            [] ->
              raise "no such dependency? #{my_dep}, "
          end
        File.rm_rf!("#{build_dir}/.mix")
    end

    # {:ok, [{:application, _the_app, app_spec}]} = :file.consult(to_charlist(Path.join([build_dir, "ebin", "#{my_dep}.app"])))
    # IO.inspect(Keyword.get(app_spec, :applications), label: "!!! Applications from #{my_dep} app spec")

    # When building erlang projects Mix likes to build them in their own directories and symlink the .beams into
    # Mix's build path.  This won't work for us since we only declare Mix's build path as our output and the links break
    for d <- File.ls!(build_dir) do
      replace_relative_symlink_with_copy(Path.join(build_dir, d))
    end

    RulesElixir.Tools.BeamStripper.start_link()
    case Path.wildcard("#{build_dir}/ebin/*.beam") do
      [] ->
        :ok
        # raise "No beams!"
      bs ->
        for beam_file <- Enum.sort(bs) do
          bin = File.read!(beam_file)
          new_bin = RulesElixir.Tools.BeamStripper.debazelify_bin(bin)
          File.write!(beam_file, new_bin)
        end
    end

    if opts[:output_archive] do
      archive_out = Path.join(top_cwd, opts[:output_archive])
      File.write!(archive_out, Archiver.create_from_dir(build_dir))
    end

  end
  
  def replace_relative_symlink_with_copy(f) do
    case File.read_link(f) do
      {:ok, link} -> 
        realpath = Path.join(Path.dirname(f), link)
        File.rm(f)
        File.cp_r!(realpath, f)
      {:error, :einval} ->
        :ok
    end
  end

  # Git catches on to our trickery if these files are symlinks (as bazel creates)
  defp fix_fake_git_repos() do
    for %{scm: Mix.SCM.Git, opts: o} <- Mix.Dep.cached(), g <- Path.wildcard(o[:dest] <> "/.git/**") do
      case File.read_link(g) do
        {:ok, realpath} ->
          File.rm!(g)
          File.cp!(realpath, g)
        _ -> :ok
      end
    end
  end
end
