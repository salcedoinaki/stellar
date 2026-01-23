defmodule StellarWeb.SpaceObjectController do
  use StellarWeb, :controller

  alias StellarData.SpaceObjects
  alias StellarData.SpaceObjects.SpaceObject
  alias StellarData.Threats

  action_fallback StellarWeb.FallbackController

  @doc """
  List all space objects with optional filters.
  
  Query parameters:
  - object_type: Filter by type (satellite, debris, rocket_body, unknown)
  - orbital_status: Filter by status (active, decayed, retired, unknown)
  - search: Search by name or NORAD ID
  - limit: Maximum number of results (default 100)
  - offset: Pagination offset (default 0)
  """
  def index(conn, params) do
    objects =
      case params["search"] do
        nil ->
          opts = build_filter_opts(params)
          SpaceObjects.list_objects(opts)

        search_query ->
          SpaceObjects.search_objects(search_query)
      end

    render(conn, :index, objects: objects)
  end

  @doc """
  Show a single space object with full details including threat assessment.
  """
  def show(conn, %{"norad_id" => norad_id}) do
    {norad_id_int, _} = Integer.parse(norad_id)
    object = SpaceObjects.get_object_by_norad_id(norad_id_int)

    case object do
      nil ->
        {:error, :not_found}

      object ->
        # Load threat assessment if it exists
        threat_assessment = Threats.get_assessment_by_object_id(object.id)
        render(conn, :show, object: object, threat_assessment: threat_assessment)
    end
  end

  @doc """
  Create a new space object.
  """
  def create(conn, %{"space_object" => space_object_params}) do
    with {:ok, %SpaceObject{} = object} <- SpaceObjects.create_object(space_object_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", "/api/objects/#{object.norad_id}")
      |> render(:show, object: object, threat_assessment: nil)
    end
  end

  @doc """
  Update a space object.
  """
  def update(conn, %{"norad_id" => norad_id, "space_object" => space_object_params}) do
    {norad_id_int, _} = Integer.parse(norad_id)
    object = SpaceObjects.get_object_by_norad_id(norad_id_int)

    case object do
      nil ->
        {:error, :not_found}

      object ->
        with {:ok, %SpaceObject{} = updated_object} <-
               SpaceObjects.update_object(object, space_object_params) do
          render(conn, :show, object: updated_object, threat_assessment: nil)
        end
    end
  end

  @doc """
  Update TLE for a space object.
  """
  def update_tle(conn, %{
        "norad_id" => norad_id,
        "tle_line1" => line1,
        "tle_line2" => line2,
        "tle_epoch" => epoch_str
      }) do
    {norad_id_int, _} = Integer.parse(norad_id)
    object = SpaceObjects.get_object_by_norad_id(norad_id_int)

    case object do
      nil ->
        {:error, :not_found}

      object ->
        with {:ok, epoch, _} <- DateTime.from_iso8601(epoch_str),
             {:ok, %SpaceObject{} = updated_object} <-
               SpaceObjects.update_tle(object, line1, line2, epoch) do
          render(conn, :show, object: updated_object, threat_assessment: nil)
        else
          {:error, _} = error -> error
        end
    end
  end

  @doc """
  Classify a space object as a threat.
  """
  def classify(conn, %{"norad_id" => norad_id, "threat_assessment" => threat_params}) do
    {norad_id_int, _} = Integer.parse(norad_id)
    object = SpaceObjects.get_object_by_norad_id(norad_id_int)

    case object do
      nil ->
        {:error, :not_found}

      object ->
        attrs = Map.put(threat_params, "space_object_id", object.id)

        # Check if assessment already exists
        case Threats.get_assessment_by_object_id(object.id) do
          nil ->
            # Create new assessment
            with {:ok, assessment} <- Threats.assess_threat(attrs) do
              render(conn, :show, object: object, threat_assessment: assessment)
            end

          existing_assessment ->
            # Update existing assessment
            with {:ok, assessment} <- Threats.update_assessment(existing_assessment, attrs) do
              render(conn, :show, object: object, threat_assessment: assessment)
            end
        end
    end
  end

  # Private functions

  defp build_filter_opts(params) do
    []
    |> maybe_add_filter(:object_type, params["object_type"])
    |> maybe_add_filter(:orbital_status, params["orbital_status"])
    |> maybe_add_filter(:limit, parse_integer(params["limit"], 100))
    |> maybe_add_filter(:offset, parse_integer(params["offset"], 0))
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_integer(nil, default), do: default
  defp parse_integer(value, default) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end
end
