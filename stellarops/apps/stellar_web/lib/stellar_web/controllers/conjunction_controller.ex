defmodule StellarWeb.ConjunctionController do
  @moduledoc """
  REST API controller for conjunction events.

  Provides endpoints for:
  - Listing upcoming conjunctions
  - Getting conjunction details
  - Filtering by satellite, severity, status
  - Triggering manual screening
  - Getting conjunction statistics
  """

  use StellarWeb, :controller

  alias StellarData.Conjunctions
  alias StellarData.Conjunctions.Conjunction
  alias StellarCore.SSA.ConjunctionDetector

  action_fallback StellarWeb.FallbackController

  @doc """
  List upcoming conjunctions with filtering.

  ## Query Parameters
  - satellite_id: Filter by satellite
  - asset_id: Filter by asset ID
  - severity: Minimum severity (low, medium, high, critical)
  - status: Filter by status (active, monitoring, resolved, expired)
  - from/tca_after: Start of time range (ISO8601)
  - to/tca_before: End of time range (ISO8601)
  - limit: Maximum results (default: 50)
  - offset: Pagination offset (default 0)
  """
  def index(conn, params) do
    opts = build_query_opts(params)

    conjunctions = if Map.get(params, "upcoming", "true") == "true" do
      Conjunctions.list_upcoming_conjunctions(opts)
    else
      Conjunctions.list_conjunctions(opts)
    end

    render(conn, :index, conjunctions: conjunctions)
  end

  @doc """
  Get critical conjunctions requiring immediate attention.
  """
  def critical(conn, _params) do
    conjunctions = Conjunctions.list_critical_conjunctions()
    render(conn, :index, conjunctions: conjunctions)
  end

  @doc """
  Get a specific conjunction by ID.
  """
  def show(conn, %{"id" => id}) do
    case Conjunctions.get_conjunction(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Conjunction not found"})

      conjunction ->
        conjunction = StellarData.Repo.preload(conjunction, [:primary_object, :secondary_object])
        asset_details = get_asset_details(conjunction.satellite_id)
        render(conn, :show, conjunction: conjunction, asset_details: asset_details)
    end
  end

  @doc """
  Acknowledge a conjunction (update status to monitoring).
  """
  def acknowledge(conn, %{"id" => id}) do
    conjunction = Conjunctions.get_conjunction!(id)

    with {:ok, %Conjunction{} = updated_conjunction} <-
           Conjunctions.update_status(conjunction, "monitoring") do
      # Broadcast update
      Phoenix.PubSub.broadcast(
        StellarData.PubSub,
        "conjunctions:all",
        {:conjunction_acknowledged, updated_conjunction}
      )

      render(conn, :show, conjunction: updated_conjunction)
    end
  end

  @doc """
  Resolve a conjunction (update status to resolved).
  """
  def resolve(conn, %{"id" => id}) do
    conjunction = Conjunctions.get_conjunction!(id)

    with {:ok, %Conjunction{} = updated_conjunction} <-
           Conjunctions.update_status(conjunction, "resolved") do
      # Broadcast update
      Phoenix.PubSub.broadcast(
        StellarData.PubSub,
        "conjunctions:all",
        {:conjunction_resolved, updated_conjunction}
      )

      render(conn, :show, conjunction: updated_conjunction)
    end
  end

  @doc """
  Get conjunctions for a specific satellite.
  """
  def for_satellite(conn, %{"satellite_id" => satellite_id} = params) do
    opts = [
      from: parse_datetime(params["from"]),
      to: parse_datetime(params["to"]),
      limit: parse_integer(params["limit"], 100)
    ]

    conjunctions = Conjunctions.list_conjunctions_for_satellite(satellite_id, opts)
    render(conn, :index, conjunctions: conjunctions)
  end

  @doc """
  Get conjunction statistics.
  """
  def statistics(conn, _params) do
    stats = Conjunctions.get_statistics()
    json(conn, %{data: stats})
  end

  @doc """
  Get count of conjunctions by severity.
  """
  def severity_counts(conn, _params) do
    counts = Conjunctions.count_by_severity()
    json(conn, %{data: counts})
  end

  @doc """
  Trigger a manual screening run.
  """
  def trigger_screening(conn, _params) do
    ConjunctionDetector.run_screening()

    json(conn, %{
      status: "screening_started",
      message: "Conjunction screening has been triggered"
    })
  end

  @doc """
  Screen a specific satellite.
  """
  def screen_satellite(conn, %{"satellite_id" => satellite_id}) do
    case ConjunctionDetector.screen_satellite(satellite_id) do
      {:ok, conjunctions} ->
        json(conn, %{
          status: "complete",
          conjunctions_found: length(conjunctions),
          data: Enum.map(conjunctions, &format_conjunction_summary/1)
        })

      {:error, :satellite_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Satellite not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end

  @doc """
  Get detector status.
  """
  def detector_status(conn, _params) do
    status = ConjunctionDetector.get_status()
    json(conn, %{data: status})
  end

  @doc """
  Update conjunction status.
  """
  def update_status(conn, %{"id" => id, "status" => new_status}) do
    status_atom = String.to_existing_atom(new_status)

    case Conjunctions.get_conjunction(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Conjunction not found"})

      conjunction ->
        case Conjunctions.update_status(conjunction, status_atom) do
          {:ok, updated} ->
            render(conn, :show, conjunction: updated)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  rescue
    ArgumentError ->
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid status value"})
  end

  @doc """
  Mark passed conjunctions as such.
  """
  def cleanup(conn, _params) do
    case Conjunctions.cleanup_passed_conjunctions() do
      {:ok, count} ->
        json(conn, %{
          status: "complete",
          updated_count: count
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end

  # Private helpers

  defp build_query_opts(params) do
    [
      satellite_id: params["satellite_id"],
      severity: parse_atom(params["severity"]),
      status: parse_atom(params["status"]),
      from: parse_datetime(params["from"] || params["tca_after"]),
      to: parse_datetime(params["to"] || params["tca_before"]),
      limit: parse_integer(params["limit"], 50),
      offset: parse_integer(params["offset"], 0),
      preload: [:primary_object, :secondary_object]
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
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

  defp format_conjunction_summary(conj) do
    %{
      tca: conj[:tca] || conj.tca,
      miss_distance_m: conj[:miss_distance_m] || conj.miss_distance_m,
      severity: conj[:severity] || :unknown
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp get_asset_details(nil), do: nil
  defp get_asset_details(asset_id) do
    # Try to get satellite state from the running system
    case StellarCore.Satellite.get_state(asset_id) do
      {:ok, state} ->
        %{
          id: asset_id,
          mode: state.mode,
          energy: state.energy,
          position: state.position,
          status: "active"
        }

      {:error, _} ->
        # Satellite might not be running, return basic info
        %{
          id: asset_id,
          status: "unknown"
        }
    end
  end
end
