defmodule StellarData.Conjunctions do
  @moduledoc """
  Context module for managing conjunction events.

  Provides CRUD operations and specialized queries for tracking
  potential collision events between space objects.
  """

  import Ecto.Query
  alias StellarData.Repo
  alias StellarData.Conjunctions.Conjunction

  @doc """
  Lists all conjunctions with optional filtering.

  ## Options
  - :satellite_id - Filter by our satellite
  - :severity - Minimum severity level
  - :status - Filter by status
  - :from - Start of time range
  - :to - End of time range
  - :limit - Maximum results
  """
  def list_conjunctions(opts \\ []) do
    Conjunction
    |> apply_filters(opts)
    |> preload([:primary_object, :secondary_object, :satellite])
    |> order_by([c], asc: c.tca)
    |> apply_limit(Keyword.get(opts, :limit))
    |> Repo.all()
  end

  @doc """
  Gets a conjunction by ID.
  """
  def get_conjunction(id) do
    Conjunction
    |> preload([:primary_object, :secondary_object, :satellite])
    |> Repo.get(id)
  end

  @doc """
  Gets a conjunction by ID, raising if not found.
  """
  def get_conjunction!(id) do
    Conjunction
    |> preload([:primary_object, :secondary_object, :satellite])
    |> Repo.get!(id)
  end

  @doc """
  Creates a new conjunction event.
  """
  def create_conjunction(attrs) do
    %Conjunction{}
    |> Conjunction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a conjunction event.
  """
  def update_conjunction(%Conjunction{} = conjunction, attrs) do
    conjunction
    |> Conjunction.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the status of a conjunction.
  """
  def update_status(%Conjunction{} = conjunction, status) do
    conjunction
    |> Conjunction.status_changeset(status)
    |> Repo.update()
  end

  @doc """
  Deletes a conjunction event.
  """
  def delete_conjunction(%Conjunction{} = conjunction) do
    Repo.delete(conjunction)
  end

  @doc """
  Gets all upcoming conjunctions (TCA in the future).
  """
  def list_upcoming_conjunctions(opts \\ []) do
    now = DateTime.utc_now()
    limit = Keyword.get(opts, :limit, 50)
    min_severity = Keyword.get(opts, :min_severity)

    query =
      Conjunction
      |> where([c], c.tca > ^now)
      |> where([c], c.status in [:predicted, :active, :monitoring])
      |> preload([:primary_object, :secondary_object, :satellite])
      |> order_by([c], asc: c.tca)
      |> limit(^limit)

    query =
      if min_severity do
        severities = severities_at_or_above(min_severity)
        where(query, [c], c.severity in ^severities)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets active (not yet passed) high-severity conjunctions.
  """
  def list_critical_conjunctions do
    now = DateTime.utc_now()

    Conjunction
    |> where([c], c.tca > ^now)
    |> where([c], c.severity in [:high, :critical])
    |> where([c], c.status in [:predicted, :active, :monitoring])
    |> preload([:primary_object, :secondary_object, :satellite])
    |> order_by([c], [desc: c.severity, asc: c.tca])
    |> Repo.all()
  end

  @doc """
  Gets conjunctions for a specific satellite.
  """
  def list_conjunctions_for_satellite(satellite_id, opts \\ []) do
    from_time = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -24 * 3600, :second))
    to_time = Keyword.get(opts, :to, DateTime.add(DateTime.utc_now(), 7 * 24 * 3600, :second))
    limit = Keyword.get(opts, :limit, 100)

    Conjunction
    |> where([c], c.satellite_id == ^satellite_id)
    |> where([c], c.tca >= ^from_time and c.tca <= ^to_time)
    |> preload([:primary_object, :secondary_object])
    |> order_by([c], asc: c.tca)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets conjunctions involving a specific space object.
  """
  def list_conjunctions_for_object(object_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Conjunction
    |> where([c], c.primary_object_id == ^object_id or c.secondary_object_id == ^object_id)
    |> preload([:primary_object, :secondary_object, :satellite])
    |> order_by([c], desc: c.tca)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets count of conjunctions by severity.
  """
  def count_by_severity do
    now = DateTime.utc_now()

    Conjunction
    |> where([c], c.tca > ^now)
    |> where([c], c.status in [:predicted, :active, :monitoring])
    |> group_by([c], c.severity)
    |> select([c], {c.severity, count(c.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Gets count of conjunctions by status.
  """
  def count_by_status do
    Conjunction
    |> group_by([c], c.status)
    |> select([c], {c.status, count(c.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Checks if a similar conjunction already exists.
  Returns the existing conjunction if found.
  """
  def find_existing_conjunction(primary_id, secondary_id, tca, tolerance_seconds \\ 60) do
    tca_min = DateTime.add(tca, -tolerance_seconds, :second)
    tca_max = DateTime.add(tca, tolerance_seconds, :second)

    Conjunction
    |> where([c], c.primary_object_id == ^primary_id and c.secondary_object_id == ^secondary_id)
    |> where([c], c.tca >= ^tca_min and c.tca <= ^tca_max)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Creates or updates a conjunction based on CDM ID or object pair + TCA.
  """
  def upsert_conjunction(attrs) do
    case attrs[:cdm_id] do
      nil ->
        # Check by object pair and TCA
        case find_existing_conjunction(
          attrs[:primary_object_id],
          attrs[:secondary_object_id],
          attrs[:tca]
        ) do
          nil -> create_conjunction(attrs)
          existing -> update_conjunction(existing, attrs)
        end

      cdm_id ->
        case Repo.get_by(Conjunction, cdm_id: cdm_id) do
          nil -> create_conjunction(attrs)
          existing -> update_conjunction(existing, attrs)
        end
    end
  end

  @doc """
  Marks old conjunctions as passed.
  """
  def cleanup_passed_conjunctions do
    now = DateTime.utc_now()

    {count, _} =
      Conjunction
      |> where([c], c.tca < ^now)
      |> where([c], c.status in [:predicted, :active, :monitoring])
      |> Repo.update_all(set: [status: :passed, last_updated: now])

    {:ok, count}
  end

  @doc """
  Assigns a COA recommendation to a conjunction.
  """
  def assign_coa(%Conjunction{} = conjunction, coa_id) do
    conjunction
    |> Conjunction.coa_changeset(coa_id)
    |> Repo.update()
  end

  @doc """
  Records that a maneuver was executed for a conjunction.
  """
  def record_maneuver(%Conjunction{} = conjunction, maneuver_id) do
    conjunction
    |> Conjunction.maneuver_changeset(maneuver_id)
    |> Repo.update()
  end

  @doc """
  Gets summary statistics for conjunctions.
  """
  def get_statistics do
    now = DateTime.utc_now()
    next_24h = DateTime.add(now, 24 * 3600, :second)
    next_7d = DateTime.add(now, 7 * 24 * 3600, :second)

    total_upcoming =
      Conjunction
      |> where([c], c.tca > ^now)
      |> where([c], c.status in [:predicted, :active, :monitoring])
      |> Repo.aggregate(:count)

    critical_24h =
      Conjunction
      |> where([c], c.tca > ^now and c.tca <= ^next_24h)
      |> where([c], c.severity in [:high, :critical])
      |> Repo.aggregate(:count)

    critical_7d =
      Conjunction
      |> where([c], c.tca > ^now and c.tca <= ^next_7d)
      |> where([c], c.severity in [:high, :critical])
      |> Repo.aggregate(:count)

    maneuvers_pending =
      Conjunction
      |> where([c], c.status == :active)
      |> where([c], not is_nil(c.recommended_coa_id))
      |> where([c], is_nil(c.executed_maneuver_id))
      |> Repo.aggregate(:count)

    %{
      total_upcoming: total_upcoming,
      critical_next_24h: critical_24h,
      critical_next_7d: critical_7d,
      maneuvers_pending: maneuvers_pending,
      by_severity: count_by_severity(),
      by_status: count_by_status()
    }
  end

  # Private helpers

  defp apply_filters(query, opts) do
    query
    |> filter_by_satellite(Keyword.get(opts, :satellite_id))
    |> filter_by_severity(Keyword.get(opts, :severity))
    |> filter_by_status(Keyword.get(opts, :status))
    |> filter_by_time_range(Keyword.get(opts, :from), Keyword.get(opts, :to))
  end

  defp filter_by_satellite(query, nil), do: query
  defp filter_by_satellite(query, satellite_id) do
    where(query, [c], c.satellite_id == ^satellite_id)
  end

  defp filter_by_severity(query, nil), do: query
  defp filter_by_severity(query, severity) do
    severities = severities_at_or_above(severity)
    where(query, [c], c.severity in ^severities)
  end

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status) do
    where(query, [c], c.status == ^status)
  end

  defp filter_by_time_range(query, nil, nil), do: query
  defp filter_by_time_range(query, from, nil) do
    where(query, [c], c.tca >= ^from)
  end
  defp filter_by_time_range(query, nil, to) do
    where(query, [c], c.tca <= ^to)
  end
  defp filter_by_time_range(query, from, to) do
    where(query, [c], c.tca >= ^from and c.tca <= ^to)
  end

  defp apply_limit(query, nil), do: query
  defp apply_limit(query, limit), do: limit(query, ^limit)

  defp severities_at_or_above(:low), do: [:low, :medium, :high, :critical]
  defp severities_at_or_above(:medium), do: [:medium, :high, :critical]
  defp severities_at_or_above(:high), do: [:high, :critical]
  defp severities_at_or_above(:critical), do: [:critical]
end
