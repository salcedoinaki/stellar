defmodule StellarData.Alarms.Alarm do
  @moduledoc """
  Ecto schema representing a system alarm.

  Alarms are raised when anomalies or issues are detected in the constellation,
  such as mission failures, low satellite energy, or ground station outages.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type severity :: :critical | :major | :minor | :warning | :info
  @type status :: :active | :acknowledged | :resolved

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "alarms" do
    field :type, :string
    field :severity, Ecto.Enum, values: [:critical, :major, :minor, :warning, :info]
    field :message, :string
    field :source, :string
    field :details, :map, default: %{}
    field :status, Ecto.Enum, values: [:active, :acknowledged, :resolved], default: :active

    # Acknowledgment and resolution
    field :acknowledged_at, :utc_datetime_usec
    field :acknowledged_by, :string
    field :resolved_at, :utc_datetime_usec

    # Optional associations
    field :satellite_id, :string
    field :mission_id, :binary_id
    field :ground_station_id, :binary_id

    timestamps()
  end

  @required_fields [:type, :severity, :message, :source]
  @optional_fields [
    :details,
    :status,
    :acknowledged_at,
    :acknowledged_by,
    :resolved_at,
    :satellite_id,
    :mission_id,
    :ground_station_id
  ]

  @doc """
  Creates a changeset for a new alarm.
  """
  def changeset(alarm, attrs) do
    alarm
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:severity, [:critical, :major, :minor, :warning, :info])
    |> validate_inclusion(:status, [:active, :acknowledged, :resolved])
    |> validate_length(:type, max: 100)
    |> validate_length(:source, max: 255)
    |> validate_length(:message, max: 1000)
    |> validate_acknowledged()
  end

  @doc """
  Changeset for acknowledging an alarm.
  """
  def acknowledge_changeset(alarm, acknowledged_by) do
    alarm
    |> change(%{
      status: :acknowledged,
      acknowledged_at: DateTime.utc_now(),
      acknowledged_by: acknowledged_by
    })
  end

  @doc """
  Changeset for resolving an alarm.
  """
  def resolve_changeset(alarm) do
    alarm
    |> change(%{
      status: :resolved,
      resolved_at: DateTime.utc_now()
    })
  end

  # Private functions

  defp validate_acknowledged(changeset) do
    case get_change(changeset, :status) do
      :acknowledged ->
        if get_field(changeset, :acknowledged_by) do
          changeset
        else
          add_error(changeset, :acknowledged_by, "is required when acknowledging an alarm")
        end

      _ ->
        changeset
    end
  end
end
