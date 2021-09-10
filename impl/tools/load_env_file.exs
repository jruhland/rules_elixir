# Script used in test driver to load environment variables which were not propagated by Bazel
# into the test environment.  Must run before `mix loadconfig` happens.

shard_index =
  case System.get_env("TEST_SHARD_INDEX") do
    nil -> 0
    tsi -> String.to_integer(tsi)
  end

hopefully_unique_port = fn port_id -> 1025 + 177 * shard_index + port_id end
{:ok, port_map} = Agent.start_link(fn -> {1, %{}} end)
uniqify_port = fn port ->
  Agent.get_and_update(port_map, fn {n, ps} ->
    if old = ps[port] do
      {old, {n, ps}}
    else
      new = hopefully_unique_port.(n)
      {new, {1+n, Map.put(ps, port, new)}}
    end
  end)
end

uniqify_port_string = fn port_str -> to_string(uniqify_port.(String.to_integer(port_str))) end
uniqify_address = fn address_str ->
  case Regex.run(~r/(.*):(\d+)/, address_str) do
    [_match, host, port] -> "#{host}:#{uniqify_port_string.(port)}"
  end
end

# Only do the complex port/address mapping bit if we are actually doing test sharding
{map_port_string, map_address} =
  case System.get_env("TEST_SHARD_INDEX") do
    nil -> {fn e -> e end, fn e -> e end}
    _ -> {uniqify_port_string, uniqify_address}
  end

load_env_vars = fn contents ->
  for line <- String.split(contents, "\n"), line != "" do
      [var, val] = String.split(line, "=", parts: 2)
      cond do
        var == "MIX_ENV" -> :nope
        String.ends_with?(var, "_PORT") ->  System.put_env(var, map_port_string.(val))
        String.ends_with?(var, "_ADDRESS") -> System.put_env(var, map_address.(val))
        true -> System.put_env(var, val)
      end
  end
end

# HACK: should plumb these properly
for f <- ["/app/config/docker-compose.common.env", "/app/config/docker-compose.ci.env"] do
    case File.read(f) do
      {:ok, cts} -> load_env_vars.(cts)
    end
end
