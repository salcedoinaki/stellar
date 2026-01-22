defmodule StellarWeb.SpaceObjectController do
  @moduledoc """
  REST API controller for space objects.

  Provides endpoints for:
  - CRUD operations on space objects
  - Threat assessment updates
  - TLE data updates
  - Search and filtering
  """

  use StellarWeb, :controller

  alias StellarData.SpaceObjects
  alias StellarData.SpaceObjects.SpaceObject

  action_fallback StellarWeb.FallbackController

  @doc """
  List space objects with filtering.

  ## Query Parameters
  - object_type: Filter by type (satellite, debris, rocket_body, unknown)
  - threat_level: Minimum threat level
  - owner: Filter by owner/nation
  - orbit_type: Filter by orbit type (leo, meo, geo, etc.)
  - status: Filter by status
  - limit: Maximum results
  - offset: Pagination offset
  """
  def index(conn, params) do
    opts = build_query_opts(params)
    space_objects = SpaceObjects.list_space_objects(opts)
    render(conn, :index, space_objects: space_objects)
  end

  @doc """
  Get a single space object by ID.
  """
  def show(conn, %{"id" => id}) do
    case SpaceObjects.get_space_object(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Space object not found"})

      space_object ->
        render(conn, :show, space_object: space_object)
    end
  end

  @doc """
  Get a space object by NORAD ID.
  """
  def show_by_norad(conn, %{"norad_id" => norad_id}) do
    case Integer.parse(norad_id) do
      {norad_int, _} ->
        case SpaceObjects.get_by_norad_id(norad_int) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Space object not found"})

          space_object ->
            render(conn, :show, space_object: space_object)
        end

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid NORAD ID"})
    end
  end

  @doc """
  Create a new space object.
  """
  def create(conn, %{"space_object" => params}) do
    case SpaceObjects.create_space_object(params) do
      {:ok, space_object} ->
        conn
        |> put_status(:created)
        |> render(:show, space_object: space_object)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  Update a space object.
  """
  def update(conn, %{"id" => id, "space_object" => params}) do
    case SpaceObjects.get_space_object(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Space object not found"})

      space_object ->
        case SpaceObjects.update_space_object(space_object, params) do
          {:ok, updated} ->
            render(conn, :show, space_object: updated)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  @doc """
  Delete a space object.
  """
  def delete(conn, %{"id" => id}) do
    case SpaceObjects.get_space_object(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Space object not found"})

      space_object ->
        case SpaceObjects.delete_space_object(space_object) do
          {:ok, _} ->
            send_resp(conn, :no_content, "")

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to delete space object"})
        end
    end
  end

  @doc """
  Update threat assessment for a space object.
  """
  def update_threat(conn, %{"id" => id} = params) do
    case SpaceObjects.get_space_object(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Space object not found"})

      space_object ->
        threat_params = %{
          threat_level: params["threat_level"],
          intel_summary: params["intel_summary"],
          capabilities: params["capabilities"],
          classification: params["classification"],
          notes: params["notes"]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.into(%{})

        case SpaceObjects.update_threat_assessment(space_object, threat_params) do
          {:ok, updated} ->
            render(conn, :show, space_object: updated)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  @doc """
  Update TLE for a space object.
  """
  def update_tle(conn, %{"id" => id, "tle_line1" => line1, "tle_line2" => line2} = params) do
    case SpaceObjects.get_space_object(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Space object not found"})

      space_object ->
        epoch = case params["tle_epoch"] do
          nil -> nil
          str ->
            case DateTime.from_iso8601(str) do
              {:ok, dt, _} -> dt
              _ -> nil
            end
        end

        case SpaceObjects.update_tle(space_object, line1, line2, epoch) do
          {:ok, updated} ->
            render(conn, :show, space_object: updated)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  @doc """
  List high threat objects.
  """
  def high_threat(conn, _params) do
    objects = SpaceObjects.list_high_threat_objects()
    render(conn, :index, space_objects: objects)
  end

  @doc """
  List objects by orbital regime.
  """
  def by_regime(conn, %{"regime" => regime}) do
    regime_atom = String.to_existing_atom(regime)
    objects = SpaceObjects.list_by_orbital_regime(regime_atom)
    render(conn, :index, space_objects: objects)
  rescue
    ArgumentError ->
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid regime. Use: leo, meo, or geo"})
  end

  @doc """
  List our protected assets.
  """
  def protected_assets(conn, _params) do
    objects = SpaceObjects.list_protected_assets()
    render(conn, :index, space_objects: objects)
  end

  @doc """
  Search objects by name.
  """
  def search(conn, %{"q" => query}) do
    objects = SpaceObjects.search_by_name(query)
    render(conn, :index, space_objects: objects)
  end

  def search(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing search query parameter 'q'"})
  end

  @doc """
  Get debris objects.
  """
  def debris(conn, _params) do
    objects = SpaceObjects.list_debris()
    render(conn, :index, space_objects: objects)
  end

  @doc """
  Get objects near a specific altitude.
  """
  def near_altitude(conn, %{"altitude_km" => alt_str} = params) do
    case Float.parse(alt_str) do
      {altitude, _} ->
        tolerance = case params["tolerance_km"] do
          nil -> 50.0
          t_str ->
            case Float.parse(t_str) do
              {t, _} -> t
              :error -> 50.0
            end
        end

        objects = SpaceObjects.list_objects_near_altitude(altitude, tolerance)
        render(conn, :index, space_objects: objects)

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid altitude value"})
    end
  end

  @doc """
  Get object counts by type.
  """
  def counts_by_type(conn, _params) do
    counts = SpaceObjects.count_by_type()
    json(conn, %{data: counts})
  end

  @doc """
  Get object counts by threat level.
  """
  def counts_by_threat(conn, _params) do
    counts = SpaceObjects.count_by_threat_level()
    json(conn, %{data: counts})
  end

  @doc """
  List objects with stale TLE data.
  """
  def stale_tle(conn, params) do
    hours = case params["hours"] do
      nil -> 24
      h_str ->
        case Integer.parse(h_str) do
          {h, _} -> h
          :error -> 24
        end
    end

    objects = SpaceObjects.list_stale_tle_objects(hours)
    render(conn, :index, space_objects: objects)
  end

  @doc """
  Link a space object to a managed satellite.
  """
  def link_to_satellite(conn, %{"id" => id, "satellite_id" => satellite_id}) do
    case SpaceObjects.get_space_object(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Space object not found"})

      space_object ->
        case SpaceObjects.link_to_satellite(space_object, satellite_id) do
          {:ok, updated} ->
            render(conn, :show, space_object: updated)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  # Private helpers

  defp build_query_opts(params) do
    [
      object_type: parse_atom(params["object_type"]),
      threat_level: parse_atom(params["threat_level"]),
      owner: params["owner"],
      orbit_type: parse_atom(params["orbit_type"]),
      status: parse_atom(params["status"]),
      limit: parse_integer(params["limit"]),
      offset: parse_integer(params["offset"])
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_atom(nil), do: nil
  defp parse_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
