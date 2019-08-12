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
    Process.put(:third_party_prefix, project_root_target.("external_dep_"))
    Process.put(:config_target, project_root_target.("config"))

    Mix.Task.run("loadconfig")

    config
    |> ReadMix.project_build_file()
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

end

