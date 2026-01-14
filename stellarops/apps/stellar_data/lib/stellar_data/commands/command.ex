defmodule StellarData.Commands.Command do
  @moduledoc """
  Ecto schema for satellite commands.

  Represents commands sent to satellites, tracking their
  status through the lifecycle: pending -> running -> done/failed/canceled.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]

  schema "commands" do
    field :command_type, :string
    field :params, :map, default: %{}
    field :status, Ecto.Enum,
      values: [:pending, :running, :done, :failed, :canceled],
      default: :pending
    field :priority, :integer, default: 0
    field :scheduled_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :result, :map
    field :error_message, :string

    belongs_to :satellite, StellarData.Satellites.Satellite, type: :string

    timestamps()
  end

  @required_fields [:satellite_id, :command_type]
  @optional_fields [
    :params,
    :status,
    :priority,
    :scheduled_at,
    :started_at,
    :completed_at,
    :result,
    :error_message
  ]

  @doc """
  Creates a changeset for a new command.
  """
  def changeset(command, attrs) do
    command
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:command_type, min: 1, max: 100)
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:satellite_id)
  end

  @doc """
  Creates a changeset for updating command status.
  """
  def status_changeset(command, attrs) do
    command
    |> cast(attrs, [:status, :started_at, :completed_at, :result, :error_message])
    |> validate_status_transition(command.status)
  end

  # Validate that status transitions are valid
  defp validate_status_transition(changeset, current_status) do
    case get_change(changeset, :status) do
      nil -> changeset
      new_status -> validate_transition(changeset, current_status, new_status)
    end
  end

  defp validate_transition(changeset, :pending, new) when new in [:running, :canceled], do: changeset
  defp validate_transition(changeset, :running, new) when new in [:done, :failed, :canceled], do: changeset
  defp validate_transition(changeset, same, same), do: changeset
  defp validate_transition(changeset, _from, _to) do
    add_error(changeset, :status, "invalid status transition")
  end
end
