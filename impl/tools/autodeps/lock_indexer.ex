defmodule RulesElixir.Tools.Autodeps.LockIndexer do
  @moduledoc """
  Deduplicates and checks all of the external dependencies encountered in all lockfiles
  """
  use GenServer
  alias RulesElixir.Tools.Autodeps.{Labeler, BuildWriter}
  alias RulesElixir.Tools.Bazel

  defmodule State, do: defstruct [
        # Remember which deps came from which lockfile; it will be useful later
        by_lockfile: %{},
        # But also keep the unique deps from every lockfile we have seen in a flat index
        index: %MapSet{}
      ]

  # Public API
  def start_link(opts),         do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def ingest(lockfile),         do: GenServer.cast(__MODULE__, {:ingest, lockfile})
  def attrs_for(lockfile),      do: GenServer.call(__MODULE__, {:attrs_for, lockfile}, :infinity)
  def attrs_for_all(),          do: GenServer.call(__MODULE__, :attrs_for_all, :infinity)
  def rules_for_all(),          do: GenServer.call(__MODULE__, :rules_for_all, :infinity)
  def label_for_lock(lockfile), do: Labeler.fully_qualified(Path.join(Path.dirname(lockfile), "mix_lock"))
  def emit(),                   do: GenServer.call(__MODULE__, :emit, :infinity)

  # Implementation
  def init(_), do: {:ok, %State{}}

  def format_status(_, _), do: %{}
  def handle_cast({:ingest, lockfile_path}, state) do
    if Map.has_key?(state.by_lockfile, lockfile_path) do
      {:noreply, state}
    else
      case File.read(lockfile_path) do
        {:error, :enoent} ->
          # This is fine becuase it probably means you didn't specify a lockfile and mix just defaulted it
          {:noreply, %{state | by_lockfile: Map.put(state.by_lockfile, lockfile_path, %{})}}
        {:ok, text} ->
          {:ok, ast} = Code.string_to_quoted(text, warn_on_unnecessary_quotes: false)
          {locks_map, _bindings} = Code.eval_quoted(ast)
          locks_attrs = for app <- Enum.sort(Map.keys(locks_map)) do
            {app, attrs_for_lock(app, locks_map[app])}
          end
          BuildWriter.emit(
            Path.join(Path.dirname(lockfile_path), "BUILD"),
            generate_rules("mix_lock", lockfile_path, locks_attrs))
          {:noreply, %{state | by_lockfile: Map.put(state.by_lockfile, lockfile_path, locks_attrs)}}
      end
    end
  end

  def handle_call({:attrs_for, lockfile_path}, _from, state) do
    case state.by_lockfile do
      %{^lockfile_path => locks_attrs} ->
        {:reply, locks_attrs, state}
      _ ->
        IO.warn("Never heard of that lockfile (#{lockfile_path})")
        {:reply, %{}, state}
    end
  end

  def handle_call(:attrs_for_all, _from, state) do
    unique_names = attrs_for_all(state)
    check_consistency(unique_names, state)
    {:reply, unique_names, state}
  end

  defp attrs_for_all(state) do
    for(
      {_lockfile, attrs_list} <- state.by_lockfile,
      {_name, attrs} <- attrs_list,
      do: {short_name(attrs), attrs}
    )
    |> Enum.group_by(fn {name, _} -> name end, fn {_, attrs} -> attrs end)
    |> Enum.map(fn {name, attrs_list} ->
      {name, Enum.reduce(attrs_list, &find_any_sha/2)}
    end)
  end

  defp generate_rules(name, lockfile_path, lock_attrs) do
    [%Bazel.Load{from: "@rules_elixir//impl:mix_lock.bzl", symbols: ["mix_lock"]},
     %Bazel.Rule{rule: "mix_lock",
                 params: [
                   name: name,
                   visibility: ["//visibility:public"],
                   lockfile: Labeler.fully_qualified(lockfile_path),
                   app_for_project: %Bazel.Map{
                     kvs: (for {app, attrs} <- lock_attrs, do: {label_for(attrs), app})}]}]
  end

  # if ANYONE has the sha, we want to make sure we pass it on to bazel...
  defp find_any_sha(a = %{bazel_sha256: sha}, %{bazel_sha256: sha}), do: a
  defp find_any_sha(a = %{bazel_sha256: _sha}, _b), do: a
  defp find_any_sha(_a, b = %{bazel_sha256: _sha}), do: b
  defp find_any_sha(a, a), do: a
  
  defp check_consistency(unique_names, state) do
    unique_deps = Enum.uniq(
      for {_lockfile, attrs_list} <- state.by_lockfile, {_name, attrs} <- attrs_list do
        Map.delete(attrs, :bazel_sha256)
      end)
    n_actually_unique = Enum.count(unique_deps)
    n_names = Enum.count(unique_names)
    if n_names != n_actually_unique do
      raise """
      Have #{to_string(n_actually_unique)} unique dependencies but #{to_string(n_names)} short names.
      Is there conflicting data in two mix.lock files?
      """
    end
  end

  def label_for(attrs), do: "@" <> short_name(attrs) <> "//:prod"
  def short_name(%{package: pkg, version: ver}) do
    to_string(pkg) <> "_" <> String.replace(ver, ".", "_")
  end
  def short_name(%{app: app, commit: commit}) do
    to_string(app) <> "_" <> commit
  end

  def attrs_for_lock(app, {:hex, pkg, ver, inner_sha, _tools, _deps, repo}) do
    %{rule: "hex_package",
      app: app,
      package: pkg,
      version: ver,
      repo: repo,
      sha: inner_sha
    }
  end

  def attrs_for_lock(app, {:hex, pkg, ver, inner_sha, _tools, _deps, repo, sha}) do 
    %{rule: "hex_package",
      app: app,
      package: pkg,
      version: ver,
      repo: repo,
      sha: inner_sha,
      bazel_sha256: sha
    }
  end

  def attrs_for_lock(app, {:git, repo, commit, _opts}) do
    %{rule: "mix_git_repository",
      app: app,
      remote: repo,
      commit: commit
    }
  end
end

