defmodule StellarData.Conjunctions do
  @moduledoc """
  Context module for managing conjunction events.
  
  Provides functions to create, update, and query conjunction events
  (close approaches between space objects).
  """

  import Ecto.Query, warn: false
  alias StellarData.Repo
  alias StellarData.Conjunctions.Conjunction
  alias StellarData.SpaceObjects.SpaceObject

  @doc """
  Returns the list of conjunctions.

  ## Options
    - :asset_id - Filter by asset ID
    - :severity - Filter by severity
    - :status - Filter by status
    - :tca_after - Filter to TCAs after this datetime
    - :tca_before - Filter to TCAs before this datetime
    - :preload - List of associations to preload
    - :limit - Limit results
    - :offset - Offset for pagination

  ## Examples

      iex> list_conjunctions()
      [%Conjunction{}, ...]

      iex> list_conjunctions(asset_id: asset_id, status: "active")
      [%Conjunction{}, ...]

  """
  def list_conjunctions(opts \\ []) do
    Conjunction
    |> apply_filters(opts)
    |> apply_pagination(opts)
    |> maybe_preload(opts[:preload])
    |> order_by([c], asc: c.tca)
    |> Repo.all()
  end

  @doc """
  Gets a single conjunction.

  Raises `Ecto.NoResultsError` if the Conjunction does not exist.

  ## Examples

      iex> get_conjunction!(123)
      %Conjunction{}

  """
  def get_conjunction!(id), do: Repo.get!(Conjunction, id)

  @doc """
  Gets a single conjunction.

  Returns `nil` if the Conjunction does not exist.
  """
  def get_conjunction(id), do: Repo.get(Conjunction, id)

  @doc """
  Creates a conjunction.

  ## Examples

      iex> create_conjunction(%{field: value})
      {:ok, %Conjunction{}}

      iex> create_conjunction(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_conjunction(attrs \\ %{}) do
    %Conjunction{}
    |> Conjunction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a conjunction.

  ## Examples

      iex> update_conjunction(conjunction, %{field: new_value})
      {:ok, %Conjunction{}}

  """
  def update_conjunction(%Conjunction{} = conjunction, attrs) do
    conjunction
    |> Conjunction.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates conjunction status.

  ## Examples

      iex> update_status(conjunction, "resolved")
      {:ok, %Conjunction{}}

  """
  def update_status(%Conjunction{} = conjunction, status) do
    conjunction
    |> Conjunction.status_changeset(%{status: status})
    |> Repo.update()
  end

  @doc """
  Deletes a conjunction.

  ## Examples

      iex> delete_conjunction(conjunction)
      {:ok, %Conjunction{}}

  """
  def delete_conjunction(%Conjunction{} = conjunction) do
    Repo.delete(conjunction)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking conjunction changes.

  ## Examples

      iex> change_conjunction(conjunction)
      %Ecto.Changeset{data: %Conjunction{}}

  """
  def change_conjunction(%Conjunction{} = conjunction, attrs \\ %{}) do
    Conjunction.changeset(conjunction, attrs)
  end

  @doc """
  Lists all active conjunctions.

  ## Examples

      iex> list_active_conjunctions()
      [%Conjunction{status: "active"}, ...]

  """
  def list_active_conjunctions do
    Conjunction
    |> where([c], c.status == :active)
    |> order_by([c], asc: c.tca)
    |> preload([:secondary_object])
    |> Repo.all()
  end

  @doc """
  Lists conjunctions for a specific asset.

  ## Examples

      iex> list_conjunctions_for_asset(asset_id)
      [%Conjunction{}, ...]

  """
  def list_conjunctions_for_asset(asset_id) do
    Conjunction
    |> where([c], c.primary_object_id == ^asset_id or c.satellite_id == ^asset_id)
    |> where([c], c.status in [:active, :monitoring])
    |> order_by([c], asc: c.tca)
    |> preload([:secondary_object])
    |> Repo.all()
  end

  @doc """
  Lists conjunctions within a time window.

  ## Examples

      iex> list_conjunctions_in_window(start_time, end_time)
      [%Conjunction{}, ...]

  """
  def list_conjunctions_in_window(start_time, end_time) do
    Conjunction
    |> where([c], c.tca >= ^start_time and c.tca <= ^end_time)
    |> order_by([c], asc: c.tca)
    |> preload(:object)
    |> Repo.all()
  end

  @doc """
  Lists upcoming conjunctions (TCA in the future).

  ## Options
    - :limit - Maximum results
    - :offset - Pagination offset
    - :preload - Associations to preload

  ## Examples

      iex> list_upcoming_conjunctions()
      [%Conjunction{}, ...]

  """
  def list_upcoming_conjunctions(opts \\ []) do
    now = DateTime.utc_now()

    Conjunction
    |> where([c], c.status in [:active, :monitoring, :predicted])
    |> where([c], c.tca >= ^now)
    |> apply_pagination(opts)
    |> maybe_preload(opts[:preload])
    |> order_by([c], asc: c.tca)
    |> Repo.all()
  end

  @doc """
  Lists conjunctions for a specific satellite.

  ## Options
    - :from - Start of time range
    - :to - End of time range
    - :limit - Maximum results

  ## Examples

      iex> list_conjunctions_for_satellite("SAT-001")
      [%Conjunction{}, ...]

  """
  def list_conjunctions_for_satellite(satellite_id, opts \\ []) do
    query = Conjunction
    |> where([c], c.satellite_id == ^satellite_id)
    |> where([c], c.status in [:active, :monitoring, :predicted])

    query = case opts[:from] do
      nil -> query
      from -> where(query, [c], c.tca >= ^from)
    end

    query = case opts[:to] do
      nil -> query
      to -> where(query, [c], c.tca <= ^to)
    end

    query
    |> limit(^(opts[:limit] || 100))
    |> order_by([c], asc: c.tca)
    |> preload([:secondary_object])
    |> Repo.all()
  end

  @doc """
  Counts active conjunctions by severity.

  ## Examples

      iex> count_by_severity()
      %{"critical" => 2, "high" => 5, "medium" => 10, "low" => 20}

  """
  def count_by_severity do
    Conjunction
    |> where([c], c.status in [:active, :monitoring, :predicted])
    |> group_by([c], c.severity)
    |> select([c], {c.severity, count(c.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Lists all critical conjunctions (high collision probability or very close approach).

  ## Examples

      iex> list_critical_conjunctions()
      [%Conjunction{severity: "critical"}, ...]

  """
  def list_critical_conjunctions do
    now = DateTime.utc_now()
    next_24h = DateTime.add(now, 24 * 60 * 60, :second)

    Conjunction
    |> where([c], c.status in [:active, :monitoring, :predicted])
    |> where([c], c.severity in [:critical, :high] or c.tca <= ^next_24h)
    |> order_by([c], asc: c.tca)
    |> preload([:secondary_object])
    |> Repo.all()
  end

  @doc """
  Returns statistics about conjunctions.

  ## Examples

      iex> get_statistics()
      %{total_active: 10, critical: 2, high: 5, ...}

  """
  def get_statistics do
    now = DateTime.utc_now()
    next_24h = DateTime.add(now, 24 * 60 * 60, :second)
    next_7d = DateTime.add(now, 7 * 24 * 60 * 60, :second)

    by_severity = count_by_severity()
    by_status = count_by_status()

    total_upcoming =
      Conjunction
      |> where([c], c.status in [:active, :monitoring, :predicted])
      |> where([c], c.tca >= ^now)
      |> Repo.aggregate(:count, :id)

    critical_24h =
      Conjunction
      |> where([c], c.status in [:active, :monitoring, :predicted])
      |> where([c], c.severity in [:critical, :high])
      |> where([c], c.tca >= ^now and c.tca <= ^next_24h)
      |> Repo.aggregate(:count, :id)

    critical_7d =
      Conjunction
      |> where([c], c.status in [:active, :monitoring, :predicted])
      |> where([c], c.severity in [:critical, :high])
      |> where([c], c.tca >= ^now and c.tca <= ^next_7d)
      |> Repo.aggregate(:count, :id)

    # Count approved maneuver COAs (pending execution)
    maneuvers_pending = 0  # Will be populated from COA module if available

    %{
      total_upcoming: total_upcoming || 0,
      critical_next_24h: critical_24h || 0,
      critical_next_7d: critical_7d || 0,
      maneuvers_pending: maneuvers_pending,
      by_severity: %{
        critical: Map.get(by_severity, :critical, 0),
        high: Map.get(by_severity, :high, 0),
        medium: Map.get(by_severity, :medium, 0),
        low: Map.get(by_severity, :low, 0)
      },
      by_status: by_status
    }
  end

  @doc """
  Counts active conjunctions by status.
  """
  def count_by_status do
    Conjunction
    |> group_by([c], c.status)
    |> select([c], {c.status, count(c.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Expires conjunctions whose TCA has passed.

  Returns the number of updated records.

  ## Examples

      iex> expire_past_conjunctions()
      {5, nil}

  """
  def expire_past_conjunctions do
    now = DateTime.utc_now()

    Conjunction
    |> where([c], c.status in [:active, :monitoring, :predicted])
    |> where([c], c.tca < ^now)
    |> Repo.update_all(set: [status: :passed, updated_at: now])
  end

  # Private functions

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:satellite_id, satellite_id}, q ->
        where(q, [c], c.satellite_id == ^satellite_id)

      {:severity, severity}, q ->
        where(q, [c], c.severity == ^severity)

      {:status, status}, q ->
        where(q, [c], c.status == ^status)

      {:tca_after, datetime}, q ->
        where(q, [c], c.tca >= ^datetime)

      {:tca_before, datetime}, q ->
        where(q, [c], c.tca <= ^datetime)

      _other, q ->
        q
    end)
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

  defp maybe_preload(query, nil), do: query
  defp maybe_preload(query, preloads), do: preload(query, ^preloads)
end
