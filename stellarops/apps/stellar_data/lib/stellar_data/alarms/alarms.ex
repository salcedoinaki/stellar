defmodule StellarData.Alarms do
  @moduledoc """
  Context module for managing alarms in the database.

  Provides CRUD operations and queries for persisted alarms.
  """

  import Ecto.Query, warn: false
  alias StellarData.Repo
  alias StellarData.Alarms.Alarm

  @doc """
  Creates a new alarm in the database.
  """
  @spec create_alarm(map()) :: {:ok, Alarm.t()} | {:error, Ecto.Changeset.t()}
  def create_alarm(attrs) do
    %Alarm{}
    |> Alarm.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an alarm by ID.
  """
  @spec get_alarm(binary()) :: {:ok, Alarm.t()} | {:error, :not_found}
  def get_alarm(id) do
    case Repo.get(Alarm, id) do
      nil -> {:error, :not_found}
      alarm -> {:ok, alarm}
    end
  end

  @doc """
  Gets an alarm by ID, raising if not found.
  """
  @spec get_alarm!(binary()) :: Alarm.t()
  def get_alarm!(id) do
    Repo.get!(Alarm, id)
  end

  @doc """
  Lists all alarms with optional filters.

  ## Options
    * `:status` - Filter by status (:active, :acknowledged, :resolved)
    * `:severity` - Filter by severity
    * `:source` - Filter by source (partial match)
    * `:satellite_id` - Filter by satellite
    * `:limit` - Limit number of results
    * `:offset` - Offset for pagination
    * `:order_by` - Field to order by (default: :inserted_at desc)
  """
  @spec list_alarms(keyword()) :: [Alarm.t()]
  def list_alarms(opts \\ []) do
    Alarm
    |> apply_filters(opts)
    |> apply_ordering(opts)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc """
  Counts alarms by status.
  """
  @spec count_by_status() :: map()
  def count_by_status do
    Alarm
    |> group_by([a], a.status)
    |> select([a], {a.status, count(a.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Counts alarms by severity (only active alarms).
  """
  @spec count_by_severity() :: map()
  def count_by_severity do
    Alarm
    |> where([a], a.status == :active)
    |> group_by([a], a.severity)
    |> select([a], {a.severity, count(a.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Gets alarm summary with counts by status and severity.
  """
  @spec get_summary() :: map()
  def get_summary do
    %{
      by_status: count_by_status(),
      by_severity: count_by_severity(),
      total_active: count_active()
    }
  end

  @doc """
  Counts active alarms.
  """
  @spec count_active() :: non_neg_integer()
  def count_active do
    Alarm
    |> where([a], a.status == :active)
    |> Repo.aggregate(:count)
  end

  @doc """
  Acknowledges an alarm.
  """
  @spec acknowledge_alarm(binary(), String.t()) :: {:ok, Alarm.t()} | {:error, term()}
  def acknowledge_alarm(id, acknowledged_by) do
    case get_alarm(id) do
      {:ok, alarm} ->
        alarm
        |> Alarm.acknowledge_changeset(acknowledged_by)
        |> Repo.update()

      error ->
        error
    end
  end

  @doc """
  Resolves an alarm.
  """
  @spec resolve_alarm(binary()) :: {:ok, Alarm.t()} | {:error, term()}
  def resolve_alarm(id) do
    case get_alarm(id) do
      {:ok, alarm} ->
        alarm
        |> Alarm.resolve_changeset()
        |> Repo.update()

      error ->
        error
    end
  end

  @doc """
  Deletes resolved alarms older than the specified seconds.
  """
  @spec clear_resolved(integer()) :: {non_neg_integer(), nil | [term()]}
  def clear_resolved(older_than_seconds \\ 86400) do
    cutoff = DateTime.add(DateTime.utc_now(), -older_than_seconds, :second)

    Alarm
    |> where([a], a.status == :resolved)
    |> where([a], a.resolved_at < ^cutoff)
    |> Repo.delete_all()
  end

  @doc """
  Finds alarms matching a specific source pattern.
  """
  @spec find_by_source(String.t()) :: [Alarm.t()]
  def find_by_source(source_pattern) do
    pattern = "%#{source_pattern}%"

    Alarm
    |> where([a], ilike(a.source, ^pattern))
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets recent active alarms for a satellite.
  """
  @spec get_satellite_alarms(String.t(), keyword()) :: [Alarm.t()]
  def get_satellite_alarms(satellite_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    Alarm
    |> where([a], a.satellite_id == ^satellite_id)
    |> where([a], a.status in [:active, :acknowledged])
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # Private helper functions

  defp apply_filters(query, opts) do
    query
    |> filter_by_status(opts[:status])
    |> filter_by_severity(opts[:severity])
    |> filter_by_source(opts[:source])
    |> filter_by_satellite(opts[:satellite_id])
    |> filter_by_type(opts[:type])
  end

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status), do: where(query, [a], a.status == ^status)

  defp filter_by_severity(query, nil), do: query
  defp filter_by_severity(query, severity), do: where(query, [a], a.severity == ^severity)

  defp filter_by_source(query, nil), do: query

  defp filter_by_source(query, source) do
    pattern = "%#{source}%"
    where(query, [a], ilike(a.source, ^pattern))
  end

  defp filter_by_satellite(query, nil), do: query
  defp filter_by_satellite(query, satellite_id), do: where(query, [a], a.satellite_id == ^satellite_id)

  defp filter_by_type(query, nil), do: query
  defp filter_by_type(query, type), do: where(query, [a], a.type == ^type)

  defp apply_ordering(query, opts) do
    case Keyword.get(opts, :order_by, {:inserted_at, :desc}) do
      {field, :desc} -> order_by(query, [a], desc: field(a, ^field))
      {field, :asc} -> order_by(query, [a], asc: field(a, ^field))
      field when is_atom(field) -> order_by(query, [a], desc: field(a, ^field))
    end
  end

  defp apply_pagination(query, opts) do
    query
    |> maybe_limit(opts[:limit])
    |> maybe_offset(opts[:offset])
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset), do: offset(query, ^offset)
end
