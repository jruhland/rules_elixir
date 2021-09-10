defmodule RulesElixir.Tools.Autodeps.MixReader do
  @moduledoc """
  Generates detailed dependency information which is only available AFTER
  all external dependencies have been fetched. 
  """

  @switches [
    # Where to find the mix project that we are going load and get the deps for.
    subdir: :string,
    mix_env: :string,
    # Information about where we are in the bazel universe, so that we can construct own own labels.
    bazel_package: :string,
    workspace_name: :string,

    dep: :keep, # Parsed by SymlinkTree
    
    generate_tests: :boolean,
    generate_images: :boolean,
    container_push_repo: :string,
    # deps metadata target, the mix_config_group needs to depend on it
    deps_meta: :string,
    output_dir: :string,
    mix_deps_cached: :string,
  ]

  alias RulesElixir.Tools.{Bazel, SymlinkTree, CachedDeps}
  alias RulesElixir.Tools.Autodeps.{Labeler, BuildWriter, LockIndexer}

  def main(argv) do

    {opts, []} = OptionParser.parse!(argv, strict: @switches)

    deps_links = SymlinkTree.parse_command_line(opts)
    output_dir = Path.absname(opts[:output_dir])
    cached_deps_file = Path.absname(opts[:mix_deps_cached])
    File.mkdir_p!(output_dir)

    top_cwd = File.cwd!()
    File.cd!(opts[:subdir])
    Mix.start()
    mix_env = String.to_atom(opts[:mix_env])
    Mix.env(mix_env)

    workspace_root = String.trim_trailing(File.cwd!(), opts[:bazel_package])

    {:ok, _sup} = Supervisor.start_link([
      Labeler.child_spec([workspace_root: workspace_root, workspace_name: opts[:workspace_name]]),
      BuildWriter.child_spec(nil),
      LockIndexer.child_spec(nil)
    ], strategy: :one_for_one)

    my_project_info = RulesElixir.Tools.Autodeps.ReposFromLock.get_mix_project_info!()
    RulesElixir.Tools.Autodeps.ReposFromLock.run([my_project_info])
    RulesElixir.Tools.Autodeps.ReposFromLock.create_elixir_filegroups([my_project_info])
    
    SymlinkTree.make_symlink_tree(Mix.Project.config()[:deps_path], deps_links)

    lockfile = Mix.Project.config()[:lockfile]

    cached_deps = CachedDeps.rehydrate(:erlang.binary_to_term(File.read!(cached_deps_file)), top_cwd)
    Mix.ProjectStack.write_cache({:cached_deps, Mix.Project.get!()}, cached_deps)
    mix_deps = Mix.Dep.cached()


    # Make sure that Mix likes all of our deps. :noappfile just means not-yet-compiled.
    for %{app: dep_app, status: {s, _} = st} <- mix_deps, s not in [:ok, :noappfile] do
      case st do
        {:overridden, %{status: ov_status}} ->
          IO.warn("Overridden dep status? #{inspect(ov_status)}")
        _ ->
          IO.puts(:stderr, [
                IO.ANSI.red(), "The dependency ",
                IO.ANSI.reset(), to_string(dep_app),
                IO.ANSI.red(), " has a bad status: #{s}\n",
                "Make sure that it is included in your mix.lock file",
                IO.ANSI.reset()
              ])
          :erlang.halt(1)
      end
    end
    
    # workspace_root = String.trim_trailing(File.cwd!(), opts[:bazel_package])
    build_file = Path.join(File.cwd!(), "BUILD")

    # Emit a mix_project_in_context for each of our REAL deps (ie, not excluded optional deps)
    real_deps = for %{app: app} <- mix_deps, into: %MapSet{}, do: app
    for dep = %{app: app, deps: deps} <- mix_deps do
      BuildWriter.emit(build_file, [
            %Bazel.Rule{
              rule: "mix_project_in_context",
              params: [
                name: to_string(app),
                like: target_for_dep(workspace_root, deps_links, dep),
                deps: Enum.sort(for d <- deps, MapSet.member?(real_deps, d.app), do: Bazel.Label.in_package(d.app))]}])
    end

    # Emit a mix_project_in_context for ourselves
    my_app_name = to_string(Mix.Project.config()[:app])
    BuildWriter.emit(build_file, [
          %Bazel.Rule{
            rule: "mix_project_in_context",
            params: [
              name: my_app_name,
              like: ":#{mix_env}",
              deps: Enum.sort(for d <- mix_deps, d.top_level, do: Bazel.Label.in_package(d.app))]}])

    # Create the mix_config_group
    config_group_name = "#{my_app_name}_#{opts[:mix_env]}_build"
    BuildWriter.emit(build_file, [
          %Bazel.Rule{
            rule: "mix_config_group",
            params: [
              name: config_group_name,
              mix_env: opts[:mix_env],
              mix_lock: opts[:deps_meta],
              root: Bazel.Label.in_package(my_app_name),
              mix_deps_cached: ":autodeps_#{mix_env}"]}])

    # Tests if we have them
    if opts[:generate_tests] do
      BuildWriter.emit(build_file, [
            %Bazel.Load{from: "@rules_elixir//impl:mix_test.bzl", symbols: ["mix_test"]},
            %Bazel.Rule{
              rule: "mix_test",
              params: [
                name: "mix_test",
                deps: [config_group_name]]}])
    end

    # Containers if we have them
    if opts[:generate_images] do
      BuildWriter.emit(build_file, [
            %Bazel.Load{from: "@rules_elixir//impl:docker_elixir.bzl", symbols: ["docker_elixir"]},
            %Bazel.Rule{
              rule: "docker_elixir",
              params: [
                name: "image_#{opts[:mix_env]}",
                env: %{
                  "MIX_ENV" => "#{opts[:mix_env]}"
                },
                build: config_group_name,
                container_push_repo: opts[:container_push_repo]]}])
    end

    # Imports and exports
    BuildWriter.emit(build_file, [
          %Bazel.Load{from: "@rules_elixir//impl:mix_rules.bzl",
                      symbols: ["mix_project2", "mix_project_in_context", "mix_config_group"]},
          %Bazel.Call{func: "exports_files",
                      args: [["mix.exs", "mix.lock"], ["//visibility:public"]]}])
    
    for {:ok, {f, id}} <- BuildWriter.get(), String.starts_with?(f, File.cwd!()) do
      File.write!(Path.join(output_dir, Path.basename(f)), id)
    end

  end

  def target_for_dep(workspace_root, deps_links, %{app: app, scm: scm, opts: opts}) do
    if opts[:in_umbrella] || scm == Mix.SCM.Path do
      Bazel.Label.in_workspace(workspace_root, Path.join(opts[:dest], to_string(opts[:env])))
    else
      case Map.fetch(deps_links, to_string(app)) do
        {:ok, path} -> 
          d = Path.basename(path)
          "@#{d}//:prod"
      end
    end
  end

end
