defmodule ReadMix do
  alias RulesElixir.Tools.Common
  def run(config) do
    cfg = Enum.into(config, %{})
    IO.puts(Common.format_rule("mix_project",
	  name: to_string(cfg.app),
	  elixirc_paths: cfg.elixirc_paths,
	  config_path: cfg.config_path,
	  deps_path: cfg.deps_path,
	  build_path: Path.relative_to(Mix.Project.build_path(config), File.cwd!())))
  end
end

File.cd!(System.get_env("BUILD_WORKING_DIRECTORY"))
Application.ensure_all_started(:mix)
Code.compile_file("mix.exs")
IO.inspect(Mix.Project.config)
IO.puts("================================================================")
ReadMix.run(Mix.Project.config)


