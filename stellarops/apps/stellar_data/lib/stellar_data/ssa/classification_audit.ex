defmodule StellarData.SSA.ClassificationAudit do
  @moduledoc """
  Schema for tracking classification changes to space objects.
  
  Provides an audit trail for all threat classification changes,
  including who made the change and when.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "classification_audits" do
    field :space_object_id, :binary_id
    field :old_classification, Ecto.Enum, values: [:hostile, :suspicious, :unknown, :friendly]
    field :new_classification, Ecto.Enum, values: [:hostile, :suspicious, :unknown, :friendly]
    field :old_threat_level, Ecto.Enum, values: [:critical, :high, :medium, :low, :none]
    field :new_threat_level, Ecto.Enum, values: [:critical, :high, :medium, :low, :none]
    field :changed_by, :string
    field :changed_at, :utc_datetime
    field :reason, :string

    timestamps()
  end

  @doc false
  def changeset(audit, attrs) do
    audit
    |> cast(attrs, [
      :space_object_id,
      :old_classification,
      :new_classification,
      :old_threat_level,
      :new_threat_level,
      :changed_by,
      :changed_at,
      :reason
    ])
    |> validate_required([:space_object_id, :new_classification, :changed_at])
    |> put_change_if_missing(:changed_at, DateTime.utc_now())
  end

  defp put_change_if_missing(changeset, field, value) do
    if get_change(changeset, field) do
      changeset
    else
      put_change(changeset, field, value)
    end
  end
end
