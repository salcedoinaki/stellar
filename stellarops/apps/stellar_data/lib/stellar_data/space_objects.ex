defmodule StellarData.SpaceObjects do
  @moduledoc """
  Context module for managing space objects.
  
  Provides functions to create, update, query, and manage space objects
  including satellites, debris, and rocket bodies.
  """

  import Ecto.Query, warn: false
  alias StellarData.Repo
  alias StellarData.SpaceObjects.SpaceObject

  @doc """
  Returns the list of space objects.

  ## Options
    - :object_type - Filter by object type
    - :orbital_status - Filter by orbital status
    - :limit - Limit number of results
    - :offset - Offset for pagination

  ## Examples

      iex> list_objects()
      [%SpaceObject{}, ...]

      iex> list_objects(object_type: "satellite", limit: 10)
      [%SpaceObject{}, ...]

  """
  def list_objects(opts \\ []) do
    SpaceObject
    |> apply_filters(opts)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc """
  Gets a single space object.

  Raises `Ecto.NoResultsError` if the SpaceObject does not exist.

  ## Examples

      iex> get_object!(123)
      %SpaceObject{}

      iex> get_object!(456)
      ** (Ecto.NoResultsError)

  """
  def get_object!(id), do: Repo.get!(SpaceObject, id)

  @doc """
  Gets a single space object.

  Returns `nil` if the SpaceObject does not exist.

  ## Examples

      iex> get_object(123)
      %SpaceObject{}

      iex> get_object(456)
      nil

  """
  def get_object(id), do: Repo.get(SpaceObject, id)

  @doc """
  Gets a space object by NORAD ID.

  ## Examples

      iex> get_object_by_norad_id(25544)
      %SpaceObject{}

      iex> get_object_by_norad_id(99999)
      nil

  """
  def get_object_by_norad_id(norad_id) do
    Repo.get_by(SpaceObject, norad_id: norad_id)
  end

  @doc """
  Creates a space object.

  ## Examples

      iex> create_object(%{field: value})
      {:ok, %SpaceObject{}}

      iex> create_object(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_object(attrs \\ %{}) do
    %SpaceObject{}
    |> SpaceObject.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a space object.

  ## Examples

      iex> update_object(space_object, %{field: new_value})
      {:ok, %SpaceObject{}}

      iex> update_object(space_object, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_object(%SpaceObject{} = space_object, attrs) do
    space_object
    |> SpaceObject.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the TLE for a space object.

  ## Examples

      iex> update_tle(space_object, tle_line1, tle_line2, epoch)
      {:ok, %SpaceObject{}}

  """
  def update_tle(%SpaceObject{} = space_object, tle_line1, tle_line2, epoch) do
    attrs = %{
      tle_line1: tle_line1,
      tle_line2: tle_line2,
      tle_epoch: epoch
    }

    space_object
    |> SpaceObject.tle_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a space object.

  ## Examples

      iex> delete_object(space_object)
      {:ok, %SpaceObject{}}

      iex> delete_object(space_object)
      {:error, %Ecto.Changeset{}}

  """
  def delete_object(%SpaceObject{} = space_object) do
    Repo.delete(space_object)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking space object changes.

  ## Examples

      iex> change_object(space_object)
      %Ecto.Changeset{data: %SpaceObject{}}

  """
  def change_object(%SpaceObject{} = space_object, attrs \\ %{}) do
    SpaceObject.changeset(space_object, attrs)
  end

  @doc """
  Search for space objects by name or NORAD ID.

  ## Examples

      iex> search_objects("ISS")
      [%SpaceObject{name: "ISS"}, ...]

      iex> search_objects("25544")
      [%SpaceObject{norad_id: 25544}]

  """
  def search_objects(query_string) when is_binary(query_string) do
    case Integer.parse(query_string) do
      {norad_id, ""} ->
        # Exact NORAD ID match
        case get_object_by_norad_id(norad_id) do
          nil -> []
          object -> [object]
        end

      _ ->
        # Name search (case-insensitive)
        pattern = "%#{query_string}%"

        SpaceObject
        |> where([o], ilike(o.name, ^pattern))
        |> limit(50)
        |> Repo.all()
    end
  end

  # Private functions

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:object_type, type}, q ->
        where(q, [o], o.object_type == ^type)

      {:orbital_status, status}, q ->
        where(q, [o], o.orbital_status == ^status)

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
end
