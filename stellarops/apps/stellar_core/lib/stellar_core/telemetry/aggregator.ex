defmodule StellarCore.Telemetry.Aggregator do
  @moduledoc """
  Telemetry aggregation service.

  Computes rolling statistics and aggregations for satellite telemetry data:
  - Rolling averages (1min, 5min, 15min, 1hr)
  - Min/max values per time window
  - Trend detection
  - Anomaly scoring

  Uses ETS for fast in-memory aggregation with periodic persistence.
  """

  use GenServer
  require Logger

  alias StellarData.Telemetry, as: TelemetryData
  alias Phoenix.PubSub

  @pubsub StellarWeb.PubSub
  @ets_table :telemetry_aggregates
  @persist_interval 60_000
  @cleanup_interval 300_000

  # Time windows in seconds
  @windows %{
    "1m" => 60,
    "5m" => 300,
    "15m" => 900,
    "1h" => 3600,
    "24h" => 86_400
  }

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a telemetry data point for aggregation.

  ## Parameters
    - satellite_id: Satellite identifier
    - metric: Metric name (e.g., "battery_voltage", "temperature")
    - value: Numeric value
    - timestamp: Optional timestamp (defaults to now)
  """
  def record(satellite_id, metric, value, timestamp \\ nil) when is_number(value) do
    GenServer.cast(__MODULE__, {:record, satellite_id, metric, value, timestamp || DateTime.utc_now()})
  end

  @doc """
  Get aggregated statistics for a satellite and metric.

  ## Returns
    Map with statistics per time window:
    %{
      "1m" => %{avg: 12.3, min: 10.0, max: 14.5, count: 60},
      "5m" => %{...},
      ...
    }
  """
  def get_stats(satellite_id, metric) do
    GenServer.call(__MODULE__, {:get_stats, satellite_id, metric})
  end

  @doc """
  Get all aggregated metrics for a satellite.
  """
  def get_all_stats(satellite_id) do
    GenServer.call(__MODULE__, {:get_all_stats, satellite_id})
  end

  @doc """
  Get trend direction for a metric.

  Returns :increasing, :decreasing, :stable, or :unknown
  """
  def get_trend(satellite_id, metric) do
    GenServer.call(__MODULE__, {:get_trend, satellite_id, metric})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    Logger.info("TelemetryAggregator starting")

    # Create ETS table for aggregates
    :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])

    # Schedule periodic tasks
    Process.send_after(self(), :persist, @persist_interval)
    Process.send_after(self(), :cleanup, @cleanup_interval)

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:record, satellite_id, metric, value, timestamp}, state) do
    key = {satellite_id, metric}
    unix_ts = DateTime.to_unix(timestamp)

    # Get or create the rolling buffer
    buffer = case :ets.lookup(@ets_table, key) do
      [{^key, buf}] -> buf
      [] -> init_buffer()
    end

    # Add to buffer and recalculate
    updated_buffer = add_to_buffer(buffer, value, unix_ts)

    :ets.insert(@ets_table, {key, updated_buffer})

    # Broadcast aggregate update if significant change
    if buffer_changed_significantly?(buffer, updated_buffer) do
      broadcast_aggregate_update(satellite_id, metric, updated_buffer)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:get_stats, satellite_id, metric}, _from, state) do
    key = {satellite_id, metric}

    stats = case :ets.lookup(@ets_table, key) do
      [{^key, buffer}] -> compute_stats(buffer)
      [] -> %{}
    end

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:get_all_stats, satellite_id}, _from, state) do
    # Find all metrics for this satellite
    pattern = {{satellite_id, :_}, :_}

    stats =
      :ets.match_object(@ets_table, pattern)
      |> Enum.map(fn {{^satellite_id, metric}, buffer} ->
        {metric, compute_stats(buffer)}
      end)
      |> Map.new()

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:get_trend, satellite_id, metric}, _from, state) do
    key = {satellite_id, metric}

    trend = case :ets.lookup(@ets_table, key) do
      [{^key, buffer}] -> calculate_trend(buffer)
      [] -> :unknown
    end

    {:reply, trend, state}
  end

  @impl true
  def handle_info(:persist, state) do
    persist_aggregates()
    Process.send_after(self(), :persist, @persist_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_data()
    Process.send_after(self(), :cleanup, @cleanup_interval)
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp init_buffer do
    %{
      # Rolling data points: [{timestamp, value}, ...]
      points: [],
      # Precomputed stats per window
      stats: %{},
      # Last update time
      updated_at: DateTime.utc_now()
    }
  end

  defp add_to_buffer(buffer, value, unix_ts) do
    # Keep points for 24 hours
    max_age = @windows["24h"]
    cutoff = unix_ts - max_age

    points = [{unix_ts, value} | buffer.points]
    |> Enum.filter(fn {ts, _v} -> ts > cutoff end)
    |> Enum.sort_by(fn {ts, _v} -> -ts end)  # Most recent first
    |> Enum.take(10_000)  # Cap at 10k points

    %{buffer | points: points, updated_at: DateTime.utc_now()}
  end

  defp compute_stats(buffer) do
    now = System.system_time(:second)

    @windows
    |> Enum.map(fn {window_name, window_seconds} ->
      cutoff = now - window_seconds

      window_points =
        buffer.points
        |> Enum.filter(fn {ts, _v} -> ts > cutoff end)
        |> Enum.map(fn {_ts, v} -> v end)

      stats = if length(window_points) > 0 do
        %{
          avg: Enum.sum(window_points) / length(window_points),
          min: Enum.min(window_points),
          max: Enum.max(window_points),
          count: length(window_points),
          stddev: calculate_stddev(window_points)
        }
      else
        nil
      end

      {window_name, stats}
    end)
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Map.new()
  end

  defp calculate_stddev([]), do: 0.0
  defp calculate_stddev([_single]), do: 0.0
  defp calculate_stddev(values) do
    avg = Enum.sum(values) / length(values)
    variance = Enum.sum(Enum.map(values, fn v -> :math.pow(v - avg, 2) end)) / length(values)
    :math.sqrt(variance)
  end

  defp calculate_trend(buffer) do
    # Use linear regression on last 5 minutes of data
    now = System.system_time(:second)
    cutoff = now - 300

    points =
      buffer.points
      |> Enum.filter(fn {ts, _v} -> ts > cutoff end)
      |> Enum.map(fn {ts, v} -> {ts - cutoff, v} end)  # Normalize timestamps

    case points do
      [] -> :unknown
      [_single] -> :stable
      points ->
        # Simple linear regression
        n = length(points)
        sum_x = Enum.sum(Enum.map(points, fn {x, _y} -> x end))
        sum_y = Enum.sum(Enum.map(points, fn {_x, y} -> y end))
        sum_xy = Enum.sum(Enum.map(points, fn {x, y} -> x * y end))
        sum_xx = Enum.sum(Enum.map(points, fn {x, _y} -> x * x end))

        denominator = n * sum_xx - sum_x * sum_x

        if denominator == 0 do
          :stable
        else
          slope = (n * sum_xy - sum_x * sum_y) / denominator
          # Normalize by average to get relative trend
          avg = sum_y / n

          relative_slope = if avg != 0, do: slope / abs(avg), else: slope

          cond do
            relative_slope > 0.01 -> :increasing
            relative_slope < -0.01 -> :decreasing
            true -> :stable
          end
        end
    end
  end

  defp buffer_changed_significantly?(old_buffer, new_buffer) do
    # Check if 1-minute stats changed by more than 5%
    old_stats = compute_stats(old_buffer)
    new_stats = compute_stats(new_buffer)

    case {Map.get(old_stats, "1m"), Map.get(new_stats, "1m")} do
      {nil, _} -> true
      {_, nil} -> false
      {old, new} ->
        if old.avg == 0 do
          new.avg != 0
        else
          abs(new.avg - old.avg) / abs(old.avg) > 0.05
        end
    end
  end

  defp broadcast_aggregate_update(satellite_id, metric, buffer) do
    stats = compute_stats(buffer)
    trend = calculate_trend(buffer)

    message = %{
      satellite_id: satellite_id,
      metric: metric,
      stats: stats,
      trend: trend,
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(
      @pubsub,
      "telemetry:aggregates",
      {:aggregate_update, message}
    )

    PubSub.broadcast(
      @pubsub,
      "satellite:#{satellite_id}:telemetry",
      {:aggregate_update, message}
    )
  end

  defp persist_aggregates do
    # Get all current aggregates and persist hourly summaries
    all_entries = :ets.tab2list(@ets_table)

    Enum.each(all_entries, fn {{satellite_id, metric}, buffer} ->
      stats = compute_stats(buffer)

      case Map.get(stats, "1h") do
        nil -> :ok
        hourly_stats ->
          TelemetryData.create_aggregate(%{
            satellite_id: satellite_id,
            metric: metric,
            window: "1h",
            avg: hourly_stats.avg,
            min: hourly_stats.min,
            max: hourly_stats.max,
            count: hourly_stats.count,
            recorded_at: DateTime.utc_now()
          })
      end
    end)

    Logger.debug("Persisted #{length(all_entries)} aggregate records")
  end

  defp cleanup_old_data do
    # Remove entries that haven't been updated in 24 hours
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -86_400, :second)

    to_delete =
      :ets.tab2list(@ets_table)
      |> Enum.filter(fn {_key, buffer} ->
        DateTime.compare(buffer.updated_at, cutoff) == :lt
      end)
      |> Enum.map(fn {key, _buffer} -> key end)

    Enum.each(to_delete, fn key ->
      :ets.delete(@ets_table, key)
    end)

    if length(to_delete) > 0 do
      Logger.debug("Cleaned up #{length(to_delete)} stale aggregate entries")
    end
  end
end
