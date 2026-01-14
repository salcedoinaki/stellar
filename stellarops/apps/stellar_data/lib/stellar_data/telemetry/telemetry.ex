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
