defmodule StellarData.Satellites do
  @moduledoc """
  Context module for satellite persistence operations.
  """

  import Ecto.Query, warn: false
  alias StellarData.Repo
  alias StellarData.Satellites.Satellite

  @doc """
  Returns the list of all satellites.
  """
  def list_satellites do
    Repo.all(Satellite)
  end

  @doc """
  Returns the list of active satellites.
  """
  def list_active_satellites do
    Satellite
    |> where([s], s.active == true)
    |> Repo.all()
  end

  @doc """
  Gets a single satellite by ID.

  Returns nil if not found.
  """
  def get_satellite(id) do
    Repo.get(Satellite, id)
  end

  @doc """
  Gets a single satellite by ID.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_satellite!(id) do
    Repo.get!(Satellite, id)
  end

  @doc """
  Creates a new satellite.
  """
  def create_satellite(attrs \\ %{}) do
    %Satellite{}
    |> Satellite.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a satellite.
  """
  def update_satellite(%Satellite{} = satellite, attrs) do
    satellite
    |> Satellite.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a satellite's runtime state (mode, energy, memory, position).
  """
  def update_satellite_state(%Satellite{} = satellite, attrs) do
    satellite
    |> Satellite.state_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a satellite's state by ID.
  """
  def update_satellite_state_by_id(id, attrs) do
    case get_satellite(id) do
      nil -> {:error, :not_found}
      satellite -> update_satellite_state(satellite, attrs)
    end
  end

  @doc """
  Deletes a satellite.
  """
  def delete_satellite(%Satellite{} = satellite) do
    Repo.delete(satellite)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking satellite changes.
  """
  def change_satellite(%Satellite{} = satellite, attrs \\ %{}) do
    Satellite.changeset(satellite, attrs)
  end

  @doc """
  Creates or updates a satellite (upsert).
  """
  def upsert_satellite(attrs) do
    %Satellite{}
    |> Satellite.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :id
    )
  end

  @doc """
  Syncs satellite state from in-memory GenServer to database.
  """
  def sync_satellite_state(id, state_map) do
    attrs = %{
      mode: state_map.mode,
      energy: state_map.energy,
      memory_used: state_map.memory_used,
      position_x: elem(state_map.position, 0),
      position_y: elem(state_map.position, 1),
      position_z: elem(state_map.position, 2)
    }

    case get_satellite(id) do
      nil ->
        create_satellite(Map.put(attrs, :id, id))

      satellite ->
        update_satellite_state(satellite, attrs)
    end
  end

  @doc """
  Returns satellites that need TLE updates.

  A satellite needs a TLE update if:
  - It has a NORAD ID
  - It's active
  - TLE was never fetched OR TLE is older than the specified max age
  """
  @spec list_satellites_needing_tle_update(keyword()) :: [Satellite.t()]
  def list_satellites_needing_tle_update(opts \\ []) do
    max_age_hours = Keyword.get(opts, :max_age_hours, 24)
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_hours, :hour)

    Satellite
    |> where([s], s.active == true)
    |> where([s], not is_nil(s.norad_id))
    |> where([s], is_nil(s.tle_updated_at) or s.tle_updated_at < ^cutoff)
    |> Repo.all()
  end

  @doc """
  Returns satellites by NORAD catalog ID.
  """
  @spec get_satellite_by_norad_id(String.t()) :: Satellite.t() | nil
  def get_satellite_by_norad_id(norad_id) do
    Satellite
    |> where([s], s.norad_id == ^norad_id)
    |> Repo.one()
  end
end
