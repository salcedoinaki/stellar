defmodule StellarWeb.ConjunctionController do
  use StellarWeb, :controller

  alias StellarData.Conjunctions
  alias StellarData.Conjunctions.Conjunction

  action_fallback StellarWeb.FallbackController

  @doc """
  List all conjunctions with optional filters.
  
  Query parameters:
  - asset_id: Filter by asset ID
  - severity: Filter by severity (critical, high, medium, low)
  - status: Filter by status (active, monitoring, resolved, expired)
  - tca_after: ISO8601 datetime - filter to TCAs after this time
  - tca_before: ISO8601 datetime - filter to TCAs before this time
  - limit: Maximum number of results (default 100)
  - offset: Pagination offset (default 0)
  """
  def index(conn, params) do
    opts = build_filter_opts(params)
    conjunctions = Conjunctions.list_conjunctions(opts)
    render(conn, :index, conjunctions: conjunctions)
  end

  @doc """
  Show a single conjunction with full details.
  """
  def show(conn, %{"id" => id}) do
    conjunction = Conjunctions.get_conjunction!(id)
    |> StellarData.Repo.preload(:object)

    # Get asset (satellite) details if available
    asset_details = get_asset_details(conjunction.asset_id)

    render(conn, :show, conjunction: conjunction, asset_details: asset_details)
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

  # Private functions

  defp build_filter_opts(params) do
    []
    |> maybe_add_filter(:asset_id, params["asset_id"])
    |> maybe_add_filter(:severity, params["severity"])
    |> maybe_add_filter(:status, params["status"])
    |> maybe_add_datetime_filter(:tca_after, params["tca_after"])
    |> maybe_add_datetime_filter(:tca_before, params["tca_before"])
    |> maybe_add_filter(:limit, parse_integer(params["limit"], 100))
    |> maybe_add_filter(:offset, parse_integer(params["offset"], 0))
    |> Keyword.put(:preload, [:object])
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_add_datetime_filter(opts, _key, nil), do: opts
  defp maybe_add_datetime_filter(opts, key, value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Keyword.put(opts, key, datetime)
      {:error, _} -> opts
    end
  end

  defp parse_integer(nil, default), do: default
  defp parse_integer(value, default) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

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
