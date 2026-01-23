defmodule StellarData.COAs do
  @moduledoc """
  Context module for Course of Action (COA) management.

  Provides functions for creating, updating, and managing COAs
  associated with conjunction events.
  """

  import Ecto.Query, warn: false
  alias StellarData.Repo
  alias StellarData.COAs.COA

  # TASK-307: Create a new COA
  @doc """
  Creates a new COA.

  ## Examples

      iex> create_coa(%{conjunction_id: uuid, type: "retrograde_burn", ...})
      {:ok, %COA{}}

  """
  def create_coa(attrs \\ %{}) do
    %COA{}
    |> COA.changeset(attrs)
    |> Repo.insert()
  end

  # TASK-308: Update an existing COA
  @doc """
  Updates a COA.

  ## Examples

      iex> update_coa(coa, %{risk_score: 25.0})
      {:ok, %COA{}}

  """
  def update_coa(%COA{} = coa, attrs) do
    coa
    |> COA.changeset(attrs)
    |> Repo.update()
  end

  # TASK-309: Get a single COA
  @doc """
  Gets a COA by ID.

  Returns `nil` if not found.
  """
  def get_coa(id) when is_binary(id) do
    Repo.get(COA, id)
  end

  def get_coa(_), do: nil

  @doc """
  Gets a COA by ID with preloaded associations.
  """
  def get_coa!(id) do
    COA
    |> Repo.get!(id)
    |> Repo.preload([:conjunction, :missions])
  end

  @doc """
  Gets a COA with its associated conjunction preloaded.
  """
  def get_coa_with_conjunction(id) do
    COA
    |> Repo.get(id)
    |> case do
      nil -> nil
      coa -> Repo.preload(coa, conjunction: [:asset, :object])
    end
  end

  # TASK-310: List COAs for a conjunction
  @doc """
  Lists all COAs for a specific conjunction.

  Returns COAs ordered by risk score (lowest first).
  """
  def list_coas_for_conjunction(conjunction_id) do
    COA
    |> where([c], c.conjunction_id == ^conjunction_id)
    |> order_by([c], asc: c.risk_score)
    |> Repo.all()
  end

  @doc """
  Lists all proposed COAs for a conjunction.
  """
  def list_proposed_coas_for_conjunction(conjunction_id) do
    COA
    |> where([c], c.conjunction_id == ^conjunction_id and c.status == :proposed)
    |> order_by([c], asc: c.risk_score)
    |> Repo.all()
  end

  # TASK-311: Select a COA
  @doc """
  Selects a COA for execution.

  This marks the COA as selected and rejects all other proposed COAs
  for the same conjunction.
  """
  def select_coa(%COA{} = coa, selected_by) do
    Repo.transaction(fn ->
      # Reject other proposed COAs for this conjunction
      reject_other_coas(coa.conjunction_id, coa.id)

      # Mark this COA as selected
      case Repo.update(COA.select_changeset(coa, selected_by)) do
        {:ok, updated_coa} -> updated_coa
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Marks a COA as executing.
  """
  def execute_coa(%COA{} = coa) do
    coa
    |> COA.execute_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a COA as completed.
  """
  def complete_coa(%COA{} = coa) do
    coa
    |> COA.complete_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a COA as failed with a reason.
  """
  def fail_coa(%COA{} = coa, reason) do
    coa
    |> COA.fail_changeset(reason)
    |> Repo.update()
  end

  @doc """
  Rejects a COA.
  """
  def reject_coa(%COA{} = coa) do
    coa
    |> COA.reject_changeset()
    |> Repo.update()
  end

  @doc """
  Deletes a COA.

  Only allows deletion of COAs in proposed or rejected status.
  """
  def delete_coa(%COA{status: status} = coa) when status in [:proposed, :rejected] do
    Repo.delete(coa)
  end

  def delete_coa(%COA{} = _coa) do
    {:error, :cannot_delete_active_coa}
  end

  @doc """
  Lists all COAs with a specific status.
  """
  def list_coas_by_status(status) do
    COA
    |> where([c], c.status == ^status)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists all executing COAs.
  """
  def list_executing_coas do
    list_coas_by_status(:executing)
  end

  @doc """
  Lists all selected COAs awaiting execution.
  """
  def list_selected_coas do
    list_coas_by_status(:selected)
  end

  @doc """
  Gets the selected COA for a conjunction.
  """
  def get_selected_coa_for_conjunction(conjunction_id) do
    COA
    |> where([c], c.conjunction_id == ^conjunction_id and c.status == :selected)
    |> Repo.one()
  end

  @doc """
  Gets the best COA (lowest risk) for a conjunction.
  """
  def get_best_coa_for_conjunction(conjunction_id) do
    COA
    |> where([c], c.conjunction_id == ^conjunction_id and c.status == :proposed)
    |> order_by([c], asc: c.risk_score)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Counts COAs for a conjunction by status.
  """
  def count_coas_for_conjunction(conjunction_id) do
    COA
    |> where([c], c.conjunction_id == ^conjunction_id)
    |> group_by([c], c.status)
    |> select([c], {c.status, count(c.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Regenerates COAs for a conjunction.

  Deletes all proposed COAs and returns the conjunction for new COA generation.
  """
  def clear_proposed_coas(conjunction_id) do
    COA
    |> where([c], c.conjunction_id == ^conjunction_id and c.status == :proposed)
    |> Repo.delete_all()
  end

  # Private helpers

  defp reject_other_coas(conjunction_id, selected_coa_id) do
    COA
    |> where([c], c.conjunction_id == ^conjunction_id)
    |> where([c], c.id != ^selected_coa_id)
    |> where([c], c.status == :proposed)
    |> Repo.update_all(set: [status: :rejected])
  end
end
