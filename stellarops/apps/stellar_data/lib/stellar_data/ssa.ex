defmodule StellarData.SSA do
  @moduledoc """
  Unified context for Space Situational Awareness (SSA) data.
  
  Provides a high-level interface for managing:
  - Space objects (satellites, debris, rocket bodies)
  - TLE data
  - Threat assessments
  - Classification audits
  
  This module consolidates SpaceObjects and Threats contexts for
  easier use by ingester modules.
  """

  alias StellarData.{SpaceObjects, Threats, Repo}
  alias StellarData.SpaceObjects.SpaceObject
  alias StellarData.Threats.ThreatAssessment
  alias StellarData.SSA.ClassificationAudit

  import Ecto.Query, warn: false

  # ============================================================================
  # Space Objects
  # ============================================================================

  @doc """
  List all space objects.
  """
  defdelegate list_space_objects(opts \\ []), to: SpaceObjects, as: :list_objects

  @doc """
  Get a space object by ID.
  """
  defdelegate get_space_object(id), to: SpaceObjects, as: :get_object

  @doc """
  Get a space object by NORAD ID.
  """
  defdelegate get_space_object_by_norad_id(norad_id), to: SpaceObjects, as: :get_object_by_norad_id

  @doc """
  Create a new space object.
  """
  defdelegate create_space_object(attrs), to: SpaceObjects, as: :create_object

  @doc """
  Update a space object.
  """
  defdelegate update_space_object(object, attrs), to: SpaceObjects, as: :update_object

  @doc """
  Search space objects by name or NORAD ID.
  """
  defdelegate search_space_objects(query), to: SpaceObjects, as: :search_objects

  # ============================================================================
  # Threat Assessments
  # ============================================================================

  @doc """
  Get threat assessment for a space object.
  """
  def get_threat_assessment(space_object_id) do
    Threats.get_assessment_by_object_id(space_object_id)
  end

  @doc """
  Create a new threat assessment.
  """
  def create_threat_assessment(attrs) do
    Threats.assess_threat(attrs)
  end

  @doc """
  Update a threat assessment.
  """
  def update_threat_assessment(assessment, attrs) do
    Threats.update_assessment(assessment, attrs)
  end

  @doc """
  List threat assessments by threat level.
  """
  def list_threat_assessments_by_level(level) do
    Threats.list_assessments(threat_level: to_string(level), preload: [:space_object])
  end

  @doc """
  List threat assessments by classification.
  """
  def list_threat_assessments_by_classification(classification) do
    Threats.list_assessments(classification: to_string(classification), preload: [:space_object])
  end

  # ============================================================================
  # Classification Audit Trail
  # ============================================================================

  @doc """
  Get classification history for a space object.
  """
  def get_threat_assessment_history(space_object_id) do
    ClassificationAudit
    |> where([a], a.space_object_id == ^space_object_id)
    |> order_by([a], desc: a.changed_at)
    |> Repo.all()
  end

  @doc """
  Create a classification audit entry.
  """
  def create_classification_audit(attrs) do
    %ClassificationAudit{}
    |> ClassificationAudit.changeset(attrs)
    |> Repo.insert()
  end

  # ============================================================================
  # TLE Statistics
  # ============================================================================

  @doc """
  Get TLE freshness statistics.
  """
  def tle_freshness_stats do
    now = DateTime.utc_now()
    stale_threshold = DateTime.add(now, -24, :hour)

    objects = list_space_objects()

    %{
      total: length(objects),
      with_tle: Enum.count(objects, & &1.tle_line1),
      fresh: Enum.count(objects, fn obj ->
        obj.tle_epoch && DateTime.compare(obj.tle_epoch, stale_threshold) == :gt
      end),
      stale: Enum.count(objects, fn obj ->
        obj.tle_epoch && DateTime.compare(obj.tle_epoch, stale_threshold) != :gt
      end)
    }
  end

  @doc """
  Get objects with stale TLEs.
  """
  def get_stale_tles(hours \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours, :hour)

    SpaceObject
    |> where([o], not is_nil(o.tle_epoch) and o.tle_epoch < ^cutoff)
    |> order_by([o], asc: o.tle_epoch)
    |> Repo.all()
  end

  # ============================================================================
  # Summary Statistics
  # ============================================================================

  @doc """
  Get overall SSA statistics.
  """
  def summary_stats do
    objects = list_space_objects()
    assessments = Threats.list_assessments()

    %{
      space_objects: %{
        total: length(objects),
        satellites: Enum.count(objects, &(&1.object_type == :satellite)),
        debris: Enum.count(objects, &(&1.object_type == :debris)),
        rocket_bodies: Enum.count(objects, &(&1.object_type == :rocket_body)),
        unknown: Enum.count(objects, &(&1.object_type == :unknown))
      },
      threats: %{
        total: length(assessments),
        hostile: Enum.count(assessments, &(&1.classification == :hostile)),
        suspicious: Enum.count(assessments, &(&1.classification == :suspicious)),
        critical: Enum.count(assessments, &(&1.threat_level == :critical)),
        high: Enum.count(assessments, &(&1.threat_level == :high))
      },
      tle: tle_freshness_stats()
    }
  end
end
