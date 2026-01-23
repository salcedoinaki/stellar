defmodule StellarWeb.SpaceObjectController do
  @moduledoc """
  REST API controller for space objects.

  Provides endpoints for:
  - CRUD operations on space objects
  - Threat assessment and classification
  - TLE data updates
  - Search and filtering
  """

  use StellarWeb, :controller

  alias StellarData.SpaceObjects
  alias StellarData.SpaceObjects.SpaceObject
  alias StellarData.Threats

  action_fallback StellarWeb.FallbackController

  # ============================================================================
  # List and Search
  # ============================================================================

  @doc """
  List space objects with filtering.

  ## Query Parameters
  - object_type: Filter by type (satellite, debris, rocket_body, unknown)
  - orbital_status: Filter by status (active, decayed, retired, unknown)
  - threat_level: Minimum threat level
  - owner: Filter by owner/nation
  - orbit_type: Filter by orbit type (leo, meo, geo, etc.)
  - search: Search by name or NORAD ID
  - limit: Maximum results (default 100)
  - offset: Pagination offset (default 0)
  """
  def index(conn, params) do
    objects =
      case params["search"] do
        nil ->
          opts = build_query_opts(params)
          SpaceObjects.list_space_objects(opts)

        search_query ->
          SpaceObjects.search_objects(search_query)
      end

    render(conn, :index, space_objects: objects)
  end

  @doc """
  Get a single space object by ID.
  """
  def show(conn, %{"id" => id}) do
    case SpaceObjects.get_space_object(id) do
      nil ->
        {:error, :not_found}

      space_object ->
        threat_assessment = Threats.get_assessment_by_object_id(space_object.id)
        render(conn, :show, space_object: space_object, threat_assessment: threat_assessment)
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
            {:error, :not_found}

          space_object ->
            threat_assessment = Threats.get_assessment_by_object_id(space_object.id)
            render(conn, :show, space_object: space_object, threat_assessment: threat_assessment)
        end

      :error ->
        {:error, :bad_request, "Invalid NORAD ID"}
    end
  end

  @doc """
  Search objects by name.
  """
  def search(conn, %{"q" => query}) do
    objects = SpaceObjects.search_by_name(query)
    render(conn, :index, space_objects: objects)
  end

  def search(conn, _params) do
    {:error, :bad_request, "Missing search query parameter 'q'"}
  end

  # ============================================================================
  # CRUD Operations
  # ============================================================================

  @doc """
  Create a new space object.
  """
  def create(conn, %{"space_object" => params}) do
    do_create(conn, params)
  end

  def create(conn, params) do
    # Handle flat params (not nested under "space_object")
    do_create(conn, params)
  end

  defp do_create(conn, params) do
    with {:ok, %SpaceObject{} = space_object} <- SpaceObjects.create_space_object(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", "/api/space_objects/#{space_object.id}")
      |> render(:show, space_object: space_object, threat_assessment: nil)
    end
  end

  @doc """
  Update a space object.
  """
  def update(conn, %{"id" => id, "space_object" => params}) do
    with space_object when not is_nil(space_object) <- SpaceObjects.get_space_object(id),
         {:ok, %SpaceObject{} = updated} <- SpaceObjects.update_space_object(space_object, params) do
      threat_assessment = Threats.get_assessment_by_object_id(updated.id)
      render(conn, :show, space_object: updated, threat_assessment: threat_assessment)
    else
      nil -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Delete a space object.
  """
  def delete(conn, %{"id" => id}) do
    with space_object when not is_nil(space_object) <- SpaceObjects.get_space_object(id),
         {:ok, _} <- SpaceObjects.delete_space_object(space_object) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, _} -> {:error, :internal_server_error, "Failed to delete space object"}
    end
  end

  # ============================================================================
  # Threat Assessment
  # ============================================================================

  @doc """
  Update threat assessment for a space object.
  """
  def update_threat(conn, %{"id" => id} = params) do
    with space_object when not is_nil(space_object) <- SpaceObjects.get_space_object(id) do
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
          threat_assessment = Threats.get_assessment_by_object_id(updated.id)
          render(conn, :show, space_object: updated, threat_assessment: threat_assessment)

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Classify a space object as a threat.
  """
  def classify(conn, %{"id" => id, "threat_assessment" => threat_params}) do
    with space_object when not is_nil(space_object) <- SpaceObjects.get_space_object(id) do
      attrs = Map.put(threat_params, "space_object_id", space_object.id)

      # Check if assessment already exists
      result =
        case Threats.get_assessment_by_object_id(space_object.id) do
          nil ->
            Threats.assess_threat(attrs)

          existing_assessment ->
            Threats.update_assessment(existing_assessment, attrs)
        end

      case result do
        {:ok, assessment} ->
          render(conn, :show, space_object: space_object, threat_assessment: assessment)

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  List high threat objects.
  """
  def high_threat(conn, _params) do
    objects = SpaceObjects.list_high_threat_objects()
    render(conn, :index, space_objects: objects)
  end

  # ============================================================================
  # TLE Operations
  # ============================================================================

  @doc """
  Update TLE for a space object.
  """
  def update_tle(conn, %{"id" => id, "tle_line1" => line1, "tle_line2" => line2} = params) do
    with space_object when not is_nil(space_object) <- SpaceObjects.get_space_object(id) do
      epoch =
        case params["tle_epoch"] do
          nil ->
            nil

          str ->
            case DateTime.from_iso8601(str) do
              {:ok, dt, _} -> dt
              _ -> nil
            end
        end

      case SpaceObjects.update_tle(space_object, line1, line2, epoch) do
        {:ok, updated} ->
          render(conn, :show, space_object: updated, threat_assessment: nil)

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  List objects with stale TLE data.
  """
  def stale_tle(conn, params) do
    hours =
      case params["hours"] do
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

  # ============================================================================
  # Orbital Queries
  # ============================================================================

  @doc """
  List objects by orbital regime.
  """
  def by_regime(conn, %{"regime" => regime}) do
    regime_atom = String.to_existing_atom(regime)
    objects = SpaceObjects.list_by_orbital_regime(regime_atom)
    render(conn, :index, space_objects: objects)
  rescue
    ArgumentError ->
      {:error, :bad_request, "Invalid regime. Use: leo, meo, or geo"}
  end

  @doc """
  Get objects near a specific altitude.
  """
  def near_altitude(conn, %{"altitude_km" => alt_str} = params) do
    case Float.parse(alt_str) do
      {altitude, _} ->
        tolerance =
          case params["tolerance_km"] do
            nil ->
              50.0

            t_str ->
              case Float.parse(t_str) do
                {t, _} -> t
                :error -> 50.0
              end
          end

        objects = SpaceObjects.list_objects_near_altitude(altitude, tolerance)
        render(conn, :index, space_objects: objects)

      :error ->
        {:error, :bad_request, "Invalid altitude value"}
    end
  end

  @doc """
  List our protected assets.
  """
  def protected_assets(conn, _params) do
    objects = SpaceObjects.list_protected_assets()
    render(conn, :index, space_objects: objects)
  end

  @doc """
  Get debris objects.
  """
  def debris(conn, _params) do
    objects = SpaceObjects.list_debris()
    render(conn, :index, space_objects: objects)
  end

  # ============================================================================
  # Statistics
  # ============================================================================

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

  # ============================================================================
  # Linking
  # ============================================================================

  @doc """
  Link a space object to a managed satellite.
  """
  def link_to_satellite(conn, %{"id" => id, "satellite_id" => satellite_id}) do
    with space_object when not is_nil(space_object) <- SpaceObjects.get_space_object(id),
         {:ok, updated} <- SpaceObjects.link_to_satellite(space_object, satellite_id) do
      render(conn, :show, space_object: updated, threat_assessment: nil)
    else
      nil -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp build_query_opts(params) do
    [
      object_type: parse_atom(params["object_type"]),
      orbital_status: parse_atom(params["orbital_status"]),
      threat_level: parse_atom(params["threat_level"]),
      owner: params["owner"],
      orbit_type: parse_atom(params["orbit_type"]),
      status: parse_atom(params["status"]),
      limit: parse_integer(params["limit"], 100),
      offset: parse_integer(params["offset"], 0)
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp parse_integer(nil, default), do: default
  defp parse_integer(str, default) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_atom(nil), do: nil
  defp parse_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end
end
