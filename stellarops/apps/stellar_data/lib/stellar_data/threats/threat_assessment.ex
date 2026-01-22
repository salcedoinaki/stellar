defmodule StellarData.Threats.ThreatAssessment do
  @moduledoc """
  Schema for threat assessments of space objects.
  
  Stores classification, capabilities, and intelligence information
  for potentially hostile or suspicious space objects.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias StellarData.SpaceObjects.SpaceObject

  @classification_values ~w(hostile suspicious unknown friendly)
  @threat_level_values ~w(critical high medium low none)
  @confidence_values ~w(high medium low)
  @capability_values ~w(isr maneuver rendezvous signals kinetic electronic)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "threat_assessments" do
    belongs_to :space_object, SpaceObject

    field :classification, :string, default: "unknown"
    field :capabilities, {:array, :string}, default: []
    field :threat_level, :string, default: "none"
    field :intel_summary, :string
    field :notes, :string
    field :assessed_by, :string
    field :assessed_at, :utc_datetime
    field :confidence_level, :string, default: "low"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a threat assessment.
  """
  def changeset(threat_assessment, attrs) do
    threat_assessment
    |> cast(attrs, [
      :space_object_id,
      :classification,
      :capabilities,
      :threat_level,
      :intel_summary,
      :notes,
      :assessed_by,
      :assessed_at,
      :confidence_level
    ])
    |> validate_required([:space_object_id, :classification, :threat_level])
    |> validate_inclusion(:classification, @classification_values)
    |> validate_inclusion(:threat_level, @threat_level_values)
    |> validate_inclusion(:confidence_level, @confidence_values)
    |> validate_capabilities()
    |> foreign_key_constraint(:space_object_id)
    |> unique_constraint(:space_object_id)
  end

  defp validate_capabilities(changeset) do
    capabilities = get_field(changeset, :capabilities) || []

    invalid_capabilities =
      Enum.reject(capabilities, &(&1 in @capability_values))

    if Enum.empty?(invalid_capabilities) do
      changeset
    else
      add_error(
        changeset,
        :capabilities,
        "contains invalid capabilities: #{Enum.join(invalid_capabilities, ", ")}"
      )
    end
  end
end
