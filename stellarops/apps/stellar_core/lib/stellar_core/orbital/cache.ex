defmodule StellarCore.Orbital.Cache do
  @moduledoc """
  Caching layer for orbital propagation requests.
  
  Uses Cachex to cache propagation results based on TLE and timestamp,
  reducing load on the orbital service for repeated requests.
  """

  require Logger

  @cache_name :orbital_cache
  @default_ttl :timer.minutes(5)

  @doc """
  Child spec for starting the cache under a supervisor.
  """
  def child_spec(opts) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)

    %{
      id: __MODULE__,
      start: {Cachex, :start_link, [@cache_name, [
        expiration: [default: ttl, interval: :timer.seconds(60), lazy: true]
      ]]},
      type: :worker
    }
  end

  @doc """
  Get a cached propagation result or execute the function and cache it.
  """
  def fetch(key, fun) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} ->
        # Cache miss - execute function and cache result
        case fun.() do
          {:ok, result} = success ->
            Cachex.put(@cache_name, key, result)
            success

          error ->
            error
        end

      {:ok, result} ->
        # Cache hit
        {:ok, result}

      {:error, _} = error ->
        # Cache error - bypass and execute function
        Logger.warning("Cache error: #{inspect(error)}, bypassing cache")
        fun.()
    end
  end

  @doc """
  Generate a cache key for a propagation request.
  """
  def propagation_key(satellite_id, tle_line1, tle_line2, timestamp) do
    # Use a hash of TLE lines to keep key size manageable
    tle_hash = :crypto.hash(:sha256, tle_line1 <> tle_line2) |> Base.encode16()
    "prop:#{satellite_id}:#{tle_hash}:#{timestamp}"
  end

  @doc """
  Generate a cache key for a trajectory request.
  """
  def trajectory_key(satellite_id, tle_line1, tle_line2, start_ts, end_ts, step) do
    tle_hash = :crypto.hash(:sha256, tle_line1 <> tle_line2) |> Base.encode16()
    "traj:#{satellite_id}:#{tle_hash}:#{start_ts}:#{end_ts}:#{step}"
  end

  @doc """
  Clear the entire cache.
  """
  def clear do
    Cachex.clear(@cache_name)
  end

  @doc """
  Get cache statistics.
  """
  def stats do
    {:ok, stats} = Cachex.stats(@cache_name)
    stats
  end

end
