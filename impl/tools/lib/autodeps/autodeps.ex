defmodule Mix.Tasks.Autodeps do
  use Mix.Task
  alias RulesElixir.Tools.{Common, Bazel, ReadMix}

  @moduledoc """
  Generate BUILD files for the mix project in the current directory
  """
  @switches [
    prefix: :string,
    echo: :boolean,
    dry_run: :boolean,
    overwrite: :boolean,
  ]

  # put our autogenerated rule in a separate file so you can build additional stuff
  @auto_build_file "BUILD.autogenerated.bzl"
  @auto_macro "autogenerated_targets"
  @load_library_helpers """
  load("@rules_elixir//impl:autogenerated_helpers.bzl", "elixir_libraries")
  """
  @load_mix_rules """
  load("@rules_elixir//impl:defs.bzl", "mix_project")
  """
  @build_file_boilerplate """
  load(":#{@auto_build_file}", "#{@auto_macro}")
  #{@auto_macro}()
  """

  @impl true
  def run(args) do
    options = parse_args(args)
    Mix.Project.get!()


    # Tuples {file, compile_dep_modules, runtime_dep_modules}
    :ets.new(:found_deps, [:set, :public, :named_table, {:write_concurrency, true}])

    # Tuples {module, file}
    :ets.new(:module_location, [:set, :public, :named_table, {:write_concurrency, true}])

    # Tuples {file, app}
    :ets.new(:file_to_app, [:set, :public, :named_table, {:write_concurrency, true}])

    # Tuples {file, defines_macros?}
    :ets.new(:file_info, [:set, :public, :named_table, {:write_concurrency, true}])

    {:ok, mixfile} = Common.active_mixfile()
    project_dir = Path.dirname(mixfile)
    config = Mix.Project.config
    wsroot = Common.workspace_root

    project_root_target = if wsroot == project_dir do
      fn tgt -> "//:" <> tgt end
    else
      fn tgt -> Common.qualified_target(project_dir <> "/" <> tgt) end
    end

    Process.put(:build_path, Mix.Project.build_path(config))
    Process.put(:third_party_target, project_root_target.("third_party"))
    Process.put(:config_target, project_root_target.("config"))

    Mix.Task.run("loadconfig")

    umbrella_deps = Enum.into(Mix.Dep.Umbrella.unloaded(), %MapSet{}, fn dep -> dep.app end)

    external_deps =
      config
      |> Mix.Project.deps_paths
      |> Map.keys
      |> Enum.filter(fn app -> not MapSet.member?(umbrella_deps, app) end)
      |> Enum.map(&to_string/1)

    Mix.Task.run("deps.compile", external_deps)
    Mix.Task.run("autodeps.recursive", options)

    generate_build_files(project_dir, options)

    targets_by_app =
      :ets.match(:file_to_app, :"$1")
      |> Enum.map(fn [{file, app}] ->
	{app, Common.qualified_target(file)}
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {app, targets} -> {app, Enum.sort(targets)} end)

    config
    |> ReadMix.project_build_file(apps_targets: %Bazel.Map{kvs: targets_by_app})
    |> write_generated_file(@load_mix_rules, project_dir, options)

  end

  defp parse_args(args) do
    {parsed, positional, invalid} =  OptionParser.parse(args, strict: @switches)
    if positional != [] do
      IO.puts("warning: positional args unsupported: #{inspect(positional)}")
    end
    if invalid != [] do
      IO.puts("warning: invalid arguments: #{inspect(invalid)}")
    end
    parsed
  end

  defp generate_build_files(project_root, opts) do
    :ets.match(:found_deps, :"$1")
    |> Enum.map(fn [{file, compile, runtime}] ->
      {Path.dirname(Path.relative_to(file, project_root)),
       elixir_library_attrs(file, compile, runtime)}
    end)
    |> Enum.group_by(
      fn {dir, _} -> dir end,
      fn {_, params} ->
        %Bazel.Map{kvs: params}
    end)
    |> Enum.map(fn {dir, all_attrs} ->
      all_attrs
      |> Enum.map(fn attrs_map ->
        # make it an atom to force quoting...
        {String.to_atom(attrs_map.kvs[:name]), attrs_map}
      end)
      |> Enum.sort_by(fn {name, _} -> name end)
      |> make_generated_body
      |> write_generated_file(@load_library_helpers, dir, opts)
    end)
  end

  defp make_generated_body(attrs_list) do
    [
      %Bazel.Infix{op: "=", left: "attrs", right: %Bazel.Map{kvs: attrs_list}},
      %Bazel.Call{func: "elixir_libraries", args: ["attrs", "overrides"]}
    ]
  end

  defp elixir_library_attrs(file, compile_deps, runtime_deps) do
    basename = Path.basename(file)
    defines_macros? = List.first(:ets.lookup(:file_info, file))
    # If we define macros, then our dependents will need ALL of our runtime deps
    exported_deps = defines_macros? && modules_to_targets(file, runtime_deps, include_third_party: true)
    [
      name: Path.rootname(basename),
      srcs: [basename],
      compile_deps: modules_to_targets(file, compile_deps, include_third_party: true),
      exported_deps: exported_deps,
      visibility: ["//visibility:public"],
    ]
  end

  defp write_generated_file(body, header, dir, opts) do
    [
      header,
      %Bazel.Def{name: @auto_macro,
                 params: [overrides: %{}],
                 body: List.wrap(body)},
      "\n",
    ]
    |> Bazel.to_iodata
    |> Common.output_file("#{dir}/#{@auto_build_file}", Keyword.put(opts, :overwrite, true))
    
    Common.output_file(@build_file_boilerplate, "#{dir}/BUILD", opts)
  end

  defp mix_dep_target(module, file) do
    buildpath = Process.get(:build_path)
    len = byte_size(buildpath)

    # Hack this for now
    case to_string(file) do
      <<prefix::binary-size(len), "/lib/", rest::binary>> when prefix == buildpath ->
	IO.puts("HACK THIS FOR NOW?? #{rest}")
	# {:ok, Process.get(:third_party_target)}
	{:ok, "external_dep_#{rest |> Path.split |> List.first}"}
      _ when module == Application ->
	{:ok, Process.get(:config_target)}
      _ when module == :application ->
	{:ok, Process.get(:config_target)}
      _ ->
	#IO.puts("!!! ERROR #{module}")
	# this should be Elixir standard internal modules
	:error
    end
  end

  defp modules_to_targets(file, modules, opts \\ []) do
    include_third_party? = Keyword.get(opts, :include_third_party, false)
    if String.contains?(file, "app_one") do
      IO.inspect({:modules_to_targets, file, include_third_party?, modules})
      IO.puts("")
    end
    modules
    |> Enum.flat_map(fn module ->

      case :ets.lookup(:module_location, module) do
        [{_, dep_file}] when dep_file != file -> [dep_file]
        _ ->
	  with\
	  true <- include_third_party?,
	  {:file, f} <- :code.is_loaded(module),
	  {:ok, target} <- mix_dep_target(module, f)
	    do [target]
	    else _ -> []
	  end
      end
    end)
    |> Enum.uniq
    |> Enum.map(fn dep_file ->
      cond do
	Path.dirname(dep_file) == Path.dirname(file) ->
	  # sibling deps first
	  {0, Common.sibling_target(dep_file)}
	String.starts_with?(dep_file, "//") ->
	  # already a target, third pary dep, sort last
	  {2, dep_file}
	true ->
	  {1, Common.qualified_target(dep_file)}
      end
    end)
    |> Enum.sort
    |> Enum.map(fn {_sort, target} -> target end)
  end

end

