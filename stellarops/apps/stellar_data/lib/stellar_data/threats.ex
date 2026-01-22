defmodule StellarData.Threats do
  @moduledoc """
  Context module for managing threat assessments.
  
  Provides functions to create, update, and query threat assessments
  for space objects.
  """

  import Ecto.Query, warn: false
  alias StellarData.Repo
  alias StellarData.Threats.ThreatAssessment
  alias StellarData.SpaceObjects.SpaceObject

  @doc """
  Returns the list of threat assessments.

  ## Options
    - :classification - Filter by classification
    - :threat_level - Filter by threat level
    - :preload - List of associations to preload

  ## Examples

      iex> list_assessments()
      [%ThreatAssessment{}, ...]

      iex> list_assessments(classification: "hostile", preload: [:space_object])
      [%ThreatAssessment{space_object: %SpaceObject{}}, ...]

  """
  def list_assessments(opts \\ []) do
    ThreatAssessment
    |> apply_filters(opts)
    |> maybe_preload(opts[:preload])
    |> Repo.all()
  end

  @doc """
  Gets a single threat assessment.

  Raises `Ecto.NoResultsError` if the ThreatAssessment does not exist.

  ## Examples

      iex> get_assessment!(123)
      %ThreatAssessment{}

  """
  def get_assessment!(id), do: Repo.get!(ThreatAssessment, id)

  @doc """
  Gets a single threat assessment.

  Returns `nil` if the ThreatAssessment does not exist.
  """
  def get_assessment(id), do: Repo.get(ThreatAssessment, id)

  @doc """
  Gets a threat assessment by space object ID.

  ## Examples

      iex> get_assessment_by_object_id(space_object_id)
      %ThreatAssessment{}

  """
  def get_assessment_by_object_id(space_object_id) do
    Repo.get_by(ThreatAssessment, space_object_id: space_object_id)
  end

  @doc """
  Creates a threat assessment.

  ## Examples

      iex> assess_threat(%{field: value})
      {:ok, %ThreatAssessment{}}

      iex> assess_threat(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def assess_threat(attrs \\ %{}) do
    attrs_with_timestamp = Map.put_new(attrs, :assessed_at, DateTime.utc_now())

    %ThreatAssessment{}
    |> ThreatAssessment.changeset(attrs_with_timestamp)
    |> Repo.insert()
  end

  @doc """
  Updates a threat assessment.

  ## Examples

      iex> update_assessment(threat_assessment, %{field: new_value})
      {:ok, %ThreatAssessment{}}

  """
  def update_assessment(%ThreatAssessment{} = threat_assessment, attrs) do
    threat_assessment
    |> ThreatAssessment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a threat assessment.

  ## Examples

      iex> delete_assessment(threat_assessment)
      {:ok, %ThreatAssessment{}}

  """
  def delete_assessment(%ThreatAssessment{} = threat_assessment) do
    Repo.delete(threat_assessment)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking threat assessment changes.

  ## Examples

      iex> change_assessment(threat_assessment)
      %Ecto.Changeset{data: %ThreatAssessment{}}

  """
  def change_assessment(%ThreatAssessment{} = threat_assessment, attrs \\ %{}) do
    ThreatAssessment.changeset(threat_assessment, attrs)
  end

  @doc """
  Lists all hostile objects with their space object data.

  ## Examples

      iex> list_hostile_objects()
      [%ThreatAssessment{classification: "hostile", space_object: %SpaceObject{}}, ...]

  """
  def list_hostile_objects do
    ThreatAssessment
    |> where([t], t.classification == "hostile")
    |> preload(:space_object)
    |> Repo.all()
  end

  @doc """
  Lists all suspicious objects with their space object data.

  ## Examples

      iex> list_suspicious_objects()
      [%ThreatAssessment{classification: "suspicious", space_object: %SpaceObject{}}, ...]

  """
  def list_suspicious_objects do
    ThreatAssessment
    |> where([t], t.classification == "suspicious")
    |> preload(:space_object)
    |> Repo.all()
  end

  @doc """
  Lists all critical threat level objects.

  ## Examples

      iex> list_critical_threats()
      [%ThreatAssessment{threat_level: "critical"}, ...]

  """
  def list_critical_threats do
    ThreatAssessment
    |> where([t], t.threat_level == "critical")
    |> preload(:space_object)
    |> order_by([t], desc: t.assessed_at)
    |> Repo.all()
  end

  # Private functions

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:classification, classification}, q ->
        where(q, [t], t.classification == ^classification)

      {:threat_level, level}, q ->
        where(q, [t], t.threat_level == ^level)

      _other, q ->
        q
    end)
  end

  defp maybe_preload(query, nil), do: query
  defp maybe_preload(query, preloads), do: preload(query, ^preloads)
end
