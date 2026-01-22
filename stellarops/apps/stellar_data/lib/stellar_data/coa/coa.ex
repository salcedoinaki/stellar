defmodule StellarData.COA do
  @moduledoc """
  Context module for Course of Action management.

  Provides CRUD operations and specialized queries for COA
  recommendations and decision tracking.
  """

  import Ecto.Query
  alias StellarData.Repo
  alias StellarData.COA.CourseOfAction

  @doc """
  Lists all COAs with optional filtering.
  """
  def list_coas(opts \\ []) do
    CourseOfAction
    |> apply_filters(opts)
    |> preload([:conjunction, :satellite])
    |> order_by([c], [desc: c.priority, desc: c.overall_score])
    |> apply_limit(Keyword.get(opts, :limit))
    |> Repo.all()
  end

  @doc """
  Gets a COA by ID.
  """
  def get_coa(id) do
    CourseOfAction
    |> preload([:conjunction, :satellite])
    |> Repo.get(id)
  end

  @doc """
  Gets a COA by ID, raising if not found.
  """
  def get_coa!(id) do
    CourseOfAction
    |> preload([:conjunction, :satellite])
    |> Repo.get!(id)
  end

  @doc """
  Creates a new COA.
  """
  def create_coa(attrs) do
    %CourseOfAction{}
    |> CourseOfAction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a COA.
  """
  def update_coa(%CourseOfAction{} = coa, attrs) do
    coa
    |> CourseOfAction.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Records a decision on a COA.
  """
  def record_decision(%CourseOfAction{} = coa, status, decided_by, notes \\ nil) do
    coa
    |> CourseOfAction.decision_changeset(%{
      status: status,
      decided_by: decided_by,
      decision_notes: notes
    })
    |> Repo.update()
  end

  @doc """
  Approves a COA.
  """
  def approve_coa(%CourseOfAction{} = coa, approved_by, notes \\ nil) do
    record_decision(coa, :approved, approved_by, notes)
  end

  @doc """
  Rejects a COA.
  """
  def reject_coa(%CourseOfAction{} = coa, rejected_by, notes \\ nil) do
    record_decision(coa, :rejected, rejected_by, notes)
  end

  @doc """
  Marks a COA as executing.
  """
  def mark_executing(%CourseOfAction{} = coa, command_id) do
    coa
    |> CourseOfAction.execution_changeset(%{
      status: :executing,
      command_id: command_id,
      execution_started_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Marks a COA as completed.
  """
  def mark_completed(%CourseOfAction{} = coa, result \\ %{}) do
    coa
    |> CourseOfAction.execution_changeset(%{
      status: :completed,
      execution_completed_at: DateTime.utc_now(),
      execution_result: result
    })
    |> Repo.update()
  end

  @doc """
  Marks a COA as failed.
  """
  def mark_failed(%CourseOfAction{} = coa, result \\ %{}) do
    coa
    |> CourseOfAction.execution_changeset(%{
      status: :failed,
      execution_completed_at: DateTime.utc_now(),
      execution_result: result
    })
    |> Repo.update()
  end

  @doc """
  Deletes a COA.
  """
  def delete_coa(%CourseOfAction{} = coa) do
    Repo.delete(coa)
  end

  @doc """
  Gets pending COAs requiring decision.
  """
  def list_pending_coas do
    CourseOfAction
    |> where([c], c.status == :proposed)
    |> preload([:conjunction, :satellite])
    |> order_by([c], [desc: c.priority, asc: c.decision_deadline])
    |> Repo.all()
  end

  @doc """
  Gets COAs for a specific satellite.
  """
  def list_coas_for_satellite(satellite_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    CourseOfAction
    |> where([c], c.satellite_id == ^satellite_id)
    |> preload([:conjunction])
    |> order_by([c], desc: c.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets COAs for a specific conjunction.
  """
  def list_coas_for_conjunction(conjunction_id) do
    CourseOfAction
    |> where([c], c.conjunction_id == ^conjunction_id)
    |> preload([:satellite])
    |> order_by([c], desc: c.overall_score)
    |> Repo.all()
  end

  @doc """
  Gets the best recommended COA for a conjunction.
  """
  def get_recommended_coa(conjunction_id) do
    CourseOfAction
    |> where([c], c.conjunction_id == ^conjunction_id)
    |> where([c], c.status in [:proposed, :approved])
    |> order_by([c], desc: c.overall_score)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets COAs with approaching decision deadlines.
  """
  def list_urgent_coas(hours_until_deadline \\ 24) do
    deadline = DateTime.add(DateTime.utc_now(), hours_until_deadline * 3600, :second)

    CourseOfAction
    |> where([c], c.status == :proposed)
    |> where([c], not is_nil(c.decision_deadline))
    |> where([c], c.decision_deadline <= ^deadline)
    |> preload([:conjunction, :satellite])
    |> order_by([c], asc: c.decision_deadline)
    |> Repo.all()
  end

  @doc """
  Gets count of COAs by status.
  """
  def count_by_status do
    CourseOfAction
    |> group_by([c], c.status)
    |> select([c], {c.status, count(c.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Supersedes old COAs when a new one is created.
  """
  def supersede_old_coas(conjunction_id, new_coa_id) do
    now = DateTime.utc_now()

    CourseOfAction
    |> where([c], c.conjunction_id == ^conjunction_id)
    |> where([c], c.id != ^new_coa_id)
    |> where([c], c.status == :proposed)
    |> Repo.update_all(set: [status: :superseded, updated_at: now])
  end

  # Private helpers

  defp apply_filters(query, opts) do
    query
    |> filter_by_satellite(Keyword.get(opts, :satellite_id))
    |> filter_by_status(Keyword.get(opts, :status))
    |> filter_by_type(Keyword.get(opts, :coa_type))
    |> filter_by_priority(Keyword.get(opts, :priority))
  end

  defp filter_by_satellite(query, nil), do: query
  defp filter_by_satellite(query, satellite_id) do
    where(query, [c], c.satellite_id == ^satellite_id)
  end

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status) do
    where(query, [c], c.status == ^status)
  end

  defp filter_by_type(query, nil), do: query
  defp filter_by_type(query, coa_type) do
    where(query, [c], c.coa_type == ^coa_type)
  end

  defp filter_by_priority(query, nil), do: query
  defp filter_by_priority(query, priority) do
    where(query, [c], c.priority == ^priority)
  end

  defp apply_limit(query, nil), do: query
  defp apply_limit(query, limit), do: limit(query, ^limit)
end
