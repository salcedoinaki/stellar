defmodule StellarData.Missions do
  @moduledoc """
  Context module for mission management.

  Provides functions for creating, scheduling, and managing satellite missions
  with priority-based scheduling and retry logic.
  """

  import Ecto.Query
  alias StellarData.Repo
  alias StellarData.Missions.Mission

  # ============================================================================
  # CRUD Operations
  # ============================================================================

  @doc """
  Creates a new mission.
  """
  def create_mission(attrs) do
    %Mission{}
    |> Mission.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a mission by ID.
  """
  def get_mission(id) do
    Repo.get(Mission, id)
  end

  @doc """
  Gets a mission by ID, raises if not found.
  """
  def get_mission!(id) do
    Repo.get!(Mission, id)
  end

  @doc """
  Updates a mission.
  """
  def update_mission(%Mission{} = mission, attrs) do
    mission
    |> Mission.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a mission.
  """
  def delete_mission(%Mission{} = mission) do
    Repo.delete(mission)
  end

  @doc """
  Lists all missions.
  """
  def list_missions do
    Repo.all(Mission)
  end

  @doc """
  Lists missions with optional filters.
  """
  def list_missions(filters) when is_map(filters) do
    Mission
    |> apply_filters(filters)
    |> Repo.all()
  end

  # ============================================================================
  # Scheduling Operations
  # ============================================================================

  @doc """
  Gets all pending missions ordered by priority and deadline.
  """
  def get_pending_missions do
    Mission
    |> where([m], m.status == :pending)
    |> where([m], is_nil(m.next_retry_at) or m.next_retry_at <= ^DateTime.utc_now())
    |> order_by([m], [
      fragment("array_position(ARRAY['critical','high','normal','low']::text[], ?::text)", m.priority),
      asc_nulls_last: m.deadline,
      asc: m.inserted_at
    ])
    |> Repo.all()
  end

  @doc """
  Gets missions for a specific satellite.
  """
  def get_satellite_missions(satellite_id, opts \\ []) do
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit)

    query =
      Mission
      |> where([m], m.satellite_id == ^satellite_id)
      |> order_by([m], desc: m.inserted_at)

    query =
      if status_filter do
        where(query, [m], m.status == ^status_filter)
      else
        query
      end

    query =
      if limit do
        limit(query, ^limit)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Schedules a mission for execution.
  """
  def schedule_mission(%Mission{status: :pending} = mission, scheduled_at) do
    mission
    |> Mission.schedule_changeset(scheduled_at)
    |> Repo.update()
  end

  def schedule_mission(%Mission{status: status}, _scheduled_at) do
    {:error, "Cannot schedule mission with status: #{status}"}
  end

  @doc """
  Starts execution of a scheduled mission.
  """
  def start_mission(%Mission{status: :scheduled} = mission) do
    mission
    |> Mission.start_changeset()
    |> Repo.update()
  end

  def start_mission(%Mission{status: status}, _scheduled_at) do
    {:error, "Cannot start mission with status: #{status}"}
  end

  @doc """
  Completes a mission successfully.
  """
  def complete_mission(%Mission{status: :running} = mission, result \\ %{}) do
    mission
    |> Mission.complete_changeset(result)
    |> Repo.update()
  end

  @doc """
  Fails a mission with retry logic.
  """
  def fail_mission(%Mission{status: :running} = mission, error) do
    mission
    |> Mission.fail_changeset(error)
    |> Repo.update()
  end

  @doc """
  Cancels a mission.
  """
  def cancel_mission(%Mission{} = mission, reason \\ "Canceled by user") do
    if mission.status in [:pending, :scheduled] do
      mission
      |> Mission.cancel_changeset(reason)
      |> Repo.update()
    else
      {:error, "Cannot cancel mission with status: #{mission.status}"}
    end
  end

  # ============================================================================
  # Query Helpers
  # ============================================================================

  @doc """
  Counts missions by status.
  """
  def count_by_status do
    Mission
    |> group_by([m], m.status)
    |> select([m], {m.status, count(m.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Gets missions that have missed their deadlines.
  """
  def get_overdue_missions do
    now = DateTime.utc_now()

    Mission
    |> where([m], m.status in [:pending, :scheduled])
    |> where([m], not is_nil(m.deadline) and m.deadline < ^now)
    |> Repo.all()
  end

  @doc """
  Gets missions that need retry.
  """
  def get_retry_ready_missions do
    now = DateTime.utc_now()

    Mission
    |> where([m], m.status == :pending)
    |> where([m], m.retry_count > 0)
    |> where([m], not is_nil(m.next_retry_at) and m.next_retry_at <= ^now)
    |> Repo.all()
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:satellite_id, id}, q -> where(q, [m], m.satellite_id == ^id)
      {:status, status}, q -> where(q, [m], m.status == ^status)
      {:priority, priority}, q -> where(q, [m], m.priority == ^priority)
      {:type, type}, q -> where(q, [m], m.type == ^type)
      _, q -> q
    end)
  end
end
