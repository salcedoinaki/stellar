defmodule StellarWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting plug using ETS for tracking request counts.

  Implements a sliding window rate limiter that tracks requests per IP address.
  Configurable limits for different endpoint categories.

  ## Configuration

  Rate limits can be configured in config:

      config :stellar_web, StellarWeb.Plugs.RateLimiter,
        enabled: true,
        default_limit: 100,
        default_window_ms: 60_000,
        limits: %{
          "api" => {100, 60_000},      # 100 requests per minute
          "missions" => {50, 60_000},  # 50 requests per minute
          "alarms" => {200, 60_000}    # 200 requests per minute
        }
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @default_limit 100
  @default_window_ms 60_000
  @table_name :stellar_rate_limit

  @impl true
  def init(opts) do
    # Ensure ETS table exists
    ensure_table_exists()

    %{
      limit: Keyword.get(opts, :limit, @default_limit),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms),
      category: Keyword.get(opts, :category, "default"),
      enabled: Keyword.get(opts, :enabled, true)
    }
  end

  @impl true
  def call(conn, %{enabled: false}), do: conn

  def call(conn, opts) do
    if rate_limiting_enabled?() do
      check_rate_limit(conn, opts)
    else
      conn
    end
  end

  defp check_rate_limit(conn, opts) do
    key = rate_limit_key(conn, opts.category)
    now = System.monotonic_time(:millisecond)
    window_start = now - opts.window_ms

    # Clean old entries and count current requests
    {count, _} = get_and_increment(key, now, window_start)

    if count > opts.limit do
      Logger.warning("Rate limit exceeded",
        ip: format_ip(conn.remote_ip),
        category: opts.category,
        count: count,
        limit: opts.limit
      )

      conn
      |> put_resp_header("x-ratelimit-limit", Integer.to_string(opts.limit))
      |> put_resp_header("x-ratelimit-remaining", "0")
      |> put_resp_header("x-ratelimit-reset", Integer.to_string(div(opts.window_ms, 1000)))
      |> put_resp_header("retry-after", Integer.to_string(div(opts.window_ms, 1000)))
      |> put_resp_content_type("application/json")
      |> send_resp(429, Jason.encode!(%{
        error: "rate_limit_exceeded",
        message: "Too many requests. Please try again later.",
        retry_after_seconds: div(opts.window_ms, 1000)
      }))
      |> halt()
    else
      remaining = max(0, opts.limit - count)

      conn
      |> put_resp_header("x-ratelimit-limit", Integer.to_string(opts.limit))
      |> put_resp_header("x-ratelimit-remaining", Integer.to_string(remaining))
      |> put_resp_header("x-ratelimit-reset", Integer.to_string(div(opts.window_ms, 1000)))
    end
  end

  defp rate_limit_key(conn, category) do
    ip = format_ip(conn.remote_ip)
    "#{category}:#{ip}"
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip({a, b, c, d, e, f, g, h}), do: "#{a}:#{b}:#{c}:#{d}:#{e}:#{f}:#{g}:#{h}"
  defp format_ip(ip), do: inspect(ip)

  defp get_and_increment(key, now, window_start) do
    # Atomic update using ETS
    case :ets.lookup(@table_name, key) do
      [{^key, timestamps}] ->
        # Filter out old timestamps
        valid_timestamps = Enum.filter(timestamps, &(&1 > window_start))
        new_timestamps = [now | valid_timestamps]
        :ets.insert(@table_name, {key, new_timestamps})
        {length(new_timestamps), new_timestamps}

      [] ->
        :ets.insert(@table_name, {key, [now]})
        {1, [now]}
    end
  end

  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])

      _ ->
        :ok
    end
  end

  defp rate_limiting_enabled? do
    Application.get_env(:stellar_web, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  @doc """
  Clears all rate limit data. Useful for testing.
  """
  def clear_all do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete_all_objects(@table_name)
    end
  end

  @doc """
  Gets current request count for a key.
  """
  def get_count(key, window_ms \\ @default_window_ms) do
    window_start = System.monotonic_time(:millisecond) - window_ms

    case :ets.lookup(@table_name, key) do
      [{^key, timestamps}] ->
        Enum.count(timestamps, &(&1 > window_start))

      [] ->
        0
    end
  end
end
