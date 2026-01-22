defmodule StellarData.Telemetry do
  @moduledoc """
  Context module for telemetry event persistence.
  """

  import Ecto.Query, warn: false
  alias StellarData.Repo
  alias StellarData.Telemetry.TelemetryEvent

  @doc """
  Records a telemetry event for a satellite.
  """
  def record_event(satellite_id, event_type, data \\ %{}) do
    %TelemetryEvent{}
    |> TelemetryEvent.changeset(%{
      satellite_id: satellite_id,
      event_type: event_type,
      data: data,
      recorded_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc """
  Creates a telemetry event from a map.
  """
  def create_event(attrs) do
    %TelemetryEvent{}
    |> TelemetryEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates multiple telemetry events in a batch.

  ## Parameters
    - events: List of event attribute maps with :satellite_id, :event_type, :payload, :recorded_at

  ## Returns
    - {:ok, count} on success
    - {:error, reason} on failure
  """
  def create_events_batch(events) when is_list(events) do
    now = DateTime.utc_now()

    entries =
      Enum.map(events, fn event ->
        %{
          id: Ecto.UUID.generate(),
          satellite_id: event.satellite_id,
          event_type: event.event_type,
          data: event[:payload] || event[:data] || %{},
          recorded_at: event[:recorded_at] || now,
          inserted_at: now,
          updated_at: now
        }
      end)

    case Repo.insert_all(TelemetryEvent, entries) do
      {count, _} -> {:ok, count}
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Gets telemetry events for a satellite.

  Options:
  - :limit - maximum number of events (default: 100)
  - :event_type - filter by event type
  - :since - only events after this timestamp
  """
  def get_events(satellite_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    event_type = Keyword.get(opts, :event_type)
    since = Keyword.get(opts, :since)

    TelemetryEvent
    |> where([e], e.satellite_id == ^satellite_id)
    |> maybe_filter_event_type(event_type)
    |> maybe_filter_since(since)
    |> order_by([e], desc: e.recorded_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets the latest telemetry event for a satellite.
  """
  def get_latest_event(satellite_id, event_type \\ nil) do
    TelemetryEvent
    |> where([e], e.satellite_id == ^satellite_id)
    |> maybe_filter_event_type(event_type)
    |> order_by([e], desc: e.recorded_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets event counts by type for a satellite.
  """
  def get_event_counts(satellite_id) do
    TelemetryEvent
    |> where([e], e.satellite_id == ^satellite_id)
    |> group_by([e], e.event_type)
    |> select([e], {e.event_type, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Deletes old telemetry events.

  Keeps only events from the last `days` days.
  """
  def prune_old_events(days \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    TelemetryEvent
    |> where([e], e.recorded_at < ^cutoff)
    |> Repo.delete_all()
  end

  @doc """
  Creates or updates a telemetry aggregate record.

  Used for storing precomputed statistics per time window.
  """
  def create_aggregate(attrs) do
    # For now, store as a telemetry event with type "aggregate"
    # In production, you'd have a dedicated aggregates table
    %TelemetryEvent{}
    |> TelemetryEvent.changeset(%{
      satellite_id: attrs.satellite_id,
      event_type: "aggregate:#{attrs.metric}:#{attrs.window}",
      data: %{
        metric: attrs.metric,
        window: attrs.window,
        avg: attrs.avg,
        min: attrs.min,
        max: attrs.max,
        count: attrs.count
      },
      recorded_at: attrs[:recorded_at] || DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc """
  Gets aggregated statistics for a satellite metric.
  """
  def get_aggregates(satellite_id, metric, opts \\ []) do
    window = Keyword.get(opts, :window)
    limit = Keyword.get(opts, :limit, 100)

    query =
      TelemetryEvent
      |> where([e], e.satellite_id == ^satellite_id)
      |> where([e], like(e.event_type, ^"aggregate:#{metric}:%"))

    query = if window do
      where(query, [e], e.event_type == ^"aggregate:#{metric}:#{window}")
    else
      query
    end

    query
    |> order_by([e], desc: e.recorded_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn event -> event.data end)
  end

  # Private helpers

  defp maybe_filter_event_type(query, nil), do: query
  defp maybe_filter_event_type(query, event_type) do
    where(query, [e], e.event_type == ^event_type)
  end

  defp maybe_filter_since(query, nil), do: query
  defp maybe_filter_since(query, since) do
    where(query, [e], e.recorded_at > ^since)
  end
end
