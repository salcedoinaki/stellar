defmodule StellarData.SpaceObjects do
  @moduledoc """
  Context module for managing space objects.

  Provides CRUD operations and specialized queries for tracking
  space objects including satellites, debris, and unknown objects.
  """

  import Ecto.Query
  alias StellarData.Repo
  alias StellarData.SpaceObjects.SpaceObject

  @doc """
  Lists all space objects with optional filtering.

  ## Options
  - :object_type - Filter by object type (:satellite, :debris, :rocket_body, :unknown)
  - :threat_level - Filter by minimum threat level
  - :owner - Filter by owner/nation
  - :orbit_type - Filter by orbit type
  - :status - Filter by status
  - :limit - Maximum number of results
  - :offset - Offset for pagination

  ## Examples
      iex> list_space_objects(object_type: :debris, limit: 100)
      [%SpaceObject{}, ...]
  """
  def list_space_objects(opts \\ []) do
    SpaceObject
    |> apply_filters(opts)
    |> apply_pagination(opts)
    |> order_by([so], desc: so.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a space object by ID.
  """
  def get_space_object(id) do
    Repo.get(SpaceObject, id)
  end

  @doc """
  Gets a space object by ID, raising if not found.
  """
  def get_space_object!(id) do
    Repo.get!(SpaceObject, id)
  end

  @doc """
  Gets a space object by NORAD ID.
  """
  def get_by_norad_id(norad_id) do
    Repo.get_by(SpaceObject, norad_id: norad_id)
  end

  @doc """
  Gets a space object by NORAD ID, raising if not found.
  """
  def get_by_norad_id!(norad_id) do
    Repo.get_by!(SpaceObject, norad_id: norad_id)
  end

  @doc """
  Creates a new space object.
  """
  def create_space_object(attrs) do
    %SpaceObject{}
    |> SpaceObject.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a space object.
  """
  def update_space_object(%SpaceObject{} = space_object, attrs) do
    space_object
    |> SpaceObject.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates threat assessment for a space object.
  """
  def update_threat_assessment(%SpaceObject{} = space_object, attrs) do
    space_object
    |> SpaceObject.threat_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates TLE data for a space object.
  """
  def update_tle(%SpaceObject{} = space_object, tle_line1, tle_line2, epoch \\ nil) do
    attrs = %{
      tle_line1: tle_line1,
      tle_line2: tle_line2,
      tle_epoch: epoch || DateTime.utc_now(),
      tle_updated_at: DateTime.utc_now()
    }

    space_object
    |> SpaceObject.tle_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a space object as observed.
  """
  def record_observation(%SpaceObject{} = space_object) do
    space_object
    |> SpaceObject.observation_changeset()
    |> Repo.update()
  end

  @doc """
  Deletes a space object.
  """
  def delete_space_object(%SpaceObject{} = space_object) do
    Repo.delete(space_object)
  end

  @doc """
  Creates or updates a space object by NORAD ID.
  """
  def upsert_by_norad_id(norad_id, attrs) do
    case get_by_norad_id(norad_id) do
      nil -> create_space_object(Map.put(attrs, :norad_id, norad_id))
      space_object -> update_space_object(space_object, attrs)
    end
  end

  @doc """
  Bulk inserts or updates space objects from TLE data.
  Returns {inserted_count, updated_count}
  """
  def bulk_upsert_from_tle(tle_entries) when is_list(tle_entries) do
    now = DateTime.utc_now()
    
    results = Enum.map(tle_entries, fn entry ->
      attrs = %{
        norad_id: entry.norad_id,
        name: entry.name,
        tle_line1: entry.tle_line1,
        tle_line2: entry.tle_line2,
        tle_epoch: entry[:tle_epoch] || now,
        tle_updated_at: now,
        data_source: entry[:data_source] || "space-track"
      }
      
      upsert_by_norad_id(entry.norad_id, attrs)
    end)

    inserted = Enum.count(results, fn
      {:ok, %{__meta__: %{state: :loaded}}} -> false
      {:ok, _} -> true
      _ -> false
    end)
    
    updated = Enum.count(results, fn
      {:ok, %{__meta__: %{state: :loaded}}} -> true
      _ -> false
    end)

    {inserted, updated}
  end

  @doc """
  Gets all objects with high threat level.
  """
  def list_high_threat_objects do
    SpaceObject
    |> where([so], so.threat_level in [:high, :critical])
    |> order_by([so], [desc: so.threat_level, desc: so.updated_at])
    |> Repo.all()
  end

  @doc """
  Gets objects in a specific orbital regime based on altitude.
  """
  def list_by_orbital_regime(regime) when regime in [:leo, :meo, :geo] do
    query = case regime do
      :leo ->
        where(SpaceObject, [so], so.apogee_km < 2000)
      :meo ->
        where(SpaceObject, [so], so.apogee_km >= 2000 and so.apogee_km < 35000)
      :geo ->
        where(SpaceObject, [so], so.apogee_km >= 35000 and so.apogee_km < 36500)
    end

    query
    |> order_by([so], asc: so.apogee_km)
    |> Repo.all()
  end

  @doc """
  Gets objects that might be in proximity to a given orbital altitude.
  """
  def list_objects_near_altitude(altitude_km, tolerance_km \\ 50) do
    min_alt = altitude_km - tolerance_km
    max_alt = altitude_km + tolerance_km

    SpaceObject
    |> where([so], so.perigee_km <= ^max_alt and so.apogee_km >= ^min_alt)
    |> order_by([so], asc: so.perigee_km)
    |> Repo.all()
  end

  @doc """
  Gets objects with similar inclination (potential collision risk).
  """
  def list_objects_by_inclination(inclination_deg, tolerance_deg \\ 2.0) do
    min_inc = inclination_deg - tolerance_deg
    max_inc = inclination_deg + tolerance_deg

    SpaceObject
    |> where([so], so.inclination_deg >= ^min_inc and so.inclination_deg <= ^max_inc)
    |> order_by([so], asc: so.inclination_deg)
    |> Repo.all()
  end

  @doc """
  Gets count of objects by type.
  """
  def count_by_type do
    SpaceObject
    |> group_by([so], so.object_type)
    |> select([so], {so.object_type, count(so.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Gets count of objects by threat level.
  """
  def count_by_threat_level do
    SpaceObject
    |> group_by([so], so.threat_level)
    |> select([so], {so.threat_level, count(so.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Gets objects with stale TLE data (older than given hours).
  """
  def list_stale_tle_objects(hours_threshold \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_threshold * 3600, :second)

    SpaceObject
    |> where([so], is_nil(so.tle_updated_at) or so.tle_updated_at < ^cutoff)
    |> order_by([so], asc: so.tle_updated_at)
    |> Repo.all()
  end

  @doc """
  Search space objects by name.
  """
  def search_by_name(query_string) do
    pattern = "%#{String.replace(query_string, "%", "\\%")}%"

    SpaceObject
    |> where([so], ilike(so.name, ^pattern))
    |> order_by([so], asc: so.name)
    |> limit(100)
    |> Repo.all()
  end

  @doc """
  Gets objects owned by a specific nation/organization.
  """
  def list_by_owner(owner) do
    SpaceObject
    |> where([so], so.owner == ^owner)
    |> order_by([so], desc: so.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets our protected assets.
  """
  def list_protected_assets do
    SpaceObject
    |> where([so], so.is_protected_asset == true)
    |> order_by([so], asc: so.name)
    |> Repo.all()
  end

  @doc """
  Links a space object to a managed satellite.
  """
  def link_to_satellite(%SpaceObject{} = space_object, satellite_id) do
    space_object
    |> Ecto.Changeset.change(%{satellite_id: satellite_id, is_protected_asset: true})
    |> Repo.update()
  end

  @doc """
  Gets all debris objects.
  """
  def list_debris do
    list_space_objects(object_type: :debris)
  end

  @doc """
  Gets recently updated objects.
  """
  def list_recently_updated(hours \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

    SpaceObject
    |> where([so], so.updated_at >= ^cutoff)
    |> order_by([so], desc: so.updated_at)
    |> Repo.all()
  end

  # Private helper functions

  defp apply_filters(query, opts) do
    query
    |> filter_by_object_type(Keyword.get(opts, :object_type))
    |> filter_by_threat_level(Keyword.get(opts, :threat_level))
    |> filter_by_owner(Keyword.get(opts, :owner))
    |> filter_by_orbit_type(Keyword.get(opts, :orbit_type))
    |> filter_by_status(Keyword.get(opts, :status))
  end

  defp filter_by_object_type(query, nil), do: query
  defp filter_by_object_type(query, type) do
    where(query, [so], so.object_type == ^type)
  end

  defp filter_by_threat_level(query, nil), do: query
  defp filter_by_threat_level(query, :none), do: query
  defp filter_by_threat_level(query, :low) do
    where(query, [so], so.threat_level in [:low, :medium, :high, :critical])
  end
  defp filter_by_threat_level(query, :medium) do
    where(query, [so], so.threat_level in [:medium, :high, :critical])
  end
  defp filter_by_threat_level(query, :high) do
    where(query, [so], so.threat_level in [:high, :critical])
  end
  defp filter_by_threat_level(query, :critical) do
    where(query, [so], so.threat_level == :critical)
  end

  defp filter_by_owner(query, nil), do: query
  defp filter_by_owner(query, owner) do
    where(query, [so], so.owner == ^owner)
  end

  defp filter_by_orbit_type(query, nil), do: query
  defp filter_by_orbit_type(query, orbit_type) do
    where(query, [so], so.orbit_type == ^orbit_type)
  end

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status) do
    where(query, [so], so.status == ^status)
  end

  defp apply_pagination(query, opts) do
    query
    |> apply_limit(Keyword.get(opts, :limit))
    |> apply_offset(Keyword.get(opts, :offset))
  end

  defp apply_limit(query, nil), do: query
  defp apply_limit(query, limit), do: limit(query, ^limit)

  defp apply_offset(query, nil), do: query
  defp apply_offset(query, offset), do: offset(query, ^offset)
end
