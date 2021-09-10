File.cd!("%%subdir%%")
Mix.start()
Mix.env(String.to_atom(System.get_env("MIX_ENV")))

Code.compile_file("mix.exs")

test_total_shards = System.get_env("TEST_TOTAL_SHARDS")
test_shard_index = System.get_env("TEST_SHARD_INDEX")

# We just need to set this var before it is read when we loadconfig; ecto.create will create the database for us
dbname =
  "bt_#{Mix.Project.config()[:app]}_#{:erlang.system_time(:second)}_#{test_shard_index || :ns}"

if String.length(dbname) > 63 do
  IO.puts(
    "Error: dbname '#{dbname}' is longer than 63 characters. Please shorten your application name if possible."
  )

  System.halt(1)
end

System.put_env("DATABASE_TEST_DB", dbname)

Mix.Task.run("loadconfig")

# Tell junit_formatter to please produce its output where Bazel expects
case System.get_env("XML_OUTPUT_FILE") do
  nil ->
    :not_in_bazel_test

  out ->
    Application.put_env(:junit_formatter, :report_dir, Path.dirname(out), persistent: true)
    Application.put_env(:junit_formatter, :report_file, Path.basename(out), persistent: true)
    Application.put_env(:junit_formatter, :prepend_project_name?, false, persistent: true)
end

Mix.Task.run("deps.loadpaths", ["--no-compile", "--no-deps-check"])

project = Mix.Project.config()
my_app = project[:app]
ecto_repos = Application.get_env(my_app, :ecto_repos, [])

if ecto_repos != [] do
  :application.ensure_all_started(:ecto_sql)
  Mix.Task.run("ecto.create", ["--no-compile", "--no-deps-check"])
  Mix.Task.run("ecto.migrate", ["--no-compile", "--no-deps-check"])
else
  case :application.ensure_all_started(:postgrex) do
    {:ok, _} ->
      {:ok, pid} = Postgrex.start_link(database: "postgres")
      Postgrex.query!(pid, "create database #{dbname}", [])

    {:error, _} ->
      :no_postgrex
  end
end

if Application.get_env(:bazel_test_helper, :warnings_as_errors, false) do
  Code.compiler_options(warnings_as_errors: true)
end

Mix.Task.run("app.start", [
  "--no-compile",
  "--no-deps-check"
  # , "--preload-modules"
])

# Load consolidated protocols
consolidated_dir = :code.lib_dir(my_app, :consolidated)
:code.add_patha(consolidated_dir)

for beam = <<"Elixir.", _rest::binary>> <- File.ls!(consolidated_dir) do
  mod = String.to_atom(Path.rootname(beam))
  :code.purge(mod)
  :code.delete(mod)
  {:module, mod} = Code.ensure_loaded(mod)
  true = Protocol.consolidated?(mod)
end

# Require and run tests ourselves so that we can filter the list of paths to implement sharding

test_dirs = project[:test_paths] || ["test"]
for t <- test_dirs, do: Code.require_file("#{t}/test_helper.exs")

test_pattern = project[:test_pattern] || "*_test.exs"
all_test_files = Enum.sort(Mix.Utils.extract_files(test_dirs, test_pattern))

which_test_files =
  if nil == test_total_shards do
    all_test_files
  else
    n_shard = String.to_integer(test_total_shards)
    i_shard = String.to_integer(test_shard_index)
    for {f, ^i_shard} <- Enum.zip(all_test_files, Stream.cycle(0..(n_shard - 1))), do: f
  end

task = Task.async(ExUnit, :run, [])

exit_code =
  try do
    case Kernel.ParallelCompiler.require(which_test_files) do
      {:ok, _mods, _} -> :ok
      {:error, _, _} -> exit({:shutdown, 1})
    end

    ExUnit.Server.modules_loaded()
    %{failures: failures} = Task.await(task, :infinity)

    if failures > 0, do: 1, else: 0
  catch
    kind, reason ->
      # In case there is an error, shut down the runner task
      # before the error propagates up and trigger links.
      Task.shutdown(task)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

:erlang.halt(exit_code)
