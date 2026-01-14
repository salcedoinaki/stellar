defmodule StellarData.Missions.Mission do
  @moduledoc """
  Ecto schema representing a satellite mission.

  A mission is a unit of work to be executed by a satellite, with:
  - Priority and deadline for scheduling
  - Resource requirements (energy, memory, bandwidth)
  - Lifecycle states with retry logic
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :pending | :scheduled | :running | :completed | :failed | :canceled
  @type priority :: :critical | :high | :normal | :low

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "missions" do
    field :name, :string
    field :description, :string
    field :type, :string  # e.g., "imaging", "data_collection", "orbit_adjust", "downlink"

    # Scheduling
    field :priority, Ecto.Enum, values: [:critical, :high, :normal, :low], default: :normal
    field :deadline, :utc_datetime_usec
    field :scheduled_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    # Lifecycle
    field :status, Ecto.Enum,
      values: [:pending, :scheduled, :running, :completed, :failed, :canceled],
      default: :pending

    # Retry logic
    field :retry_count, :integer, default: 0
    field :max_retries, :integer, default: 3
    field :next_retry_at, :utc_datetime_usec
    field :last_error, :string

    # Resource requirements
    field :required_energy, :float, default: 10.0
    field :required_memory, :float, default: 5.0
    field :required_bandwidth, :float, default: 1.0  # Mbps
    field :estimated_duration, :integer, default: 300  # seconds

    # Payload (flexible JSON for mission-specific data)
    field :payload, :map, default: %{}
    field :result, :map

    # Relationships
    field :satellite_id, :string
    field :ground_station_id, :binary_id

    timestamps()
  end

  @required_fields [:name, :type, :satellite_id]
  @optional_fields [
    :description,
    :priority,
    :deadline,
    :scheduled_at,
    :started_at,
    :completed_at,
    :status,
    :retry_count,
    :max_retries,
    :next_retry_at,
    :last_error,
    :required_energy,
    :required_memory,
    :required_bandwidth,
    :estimated_duration,
    :payload,
    :result,
    :ground_station_id
  ]

  @doc """
  Creates a changeset for a new mission.
  """
  def changeset(mission, attrs) do
    mission
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:priority, [:critical, :high, :normal, :low])
    |> validate_inclusion(:status, [:pending, :scheduled, :running, :completed, :failed, :canceled])
    |> validate_number(:required_energy, greater_than: 0)
    |> validate_number(:required_memory, greater_than_or_equal_to: 0)
    |> validate_number(:required_bandwidth, greater_than_or_equal_to: 0)
    |> validate_number(:estimated_duration, greater_than: 0)
    |> validate_number(:retry_count, greater_than_or_equal_to: 0)
    |> validate_number(:max_retries, greater_than_or_equal_to: 0)
    |> validate_deadline()
  end

  @doc """
  Changeset for scheduling a mission.
  """
  def schedule_changeset(mission, scheduled_at) do
    mission
    |> change(%{
      status: :scheduled,
      scheduled_at: scheduled_at
    })
  end

  @doc """
  Changeset for starting a mission.
  """
  def start_changeset(mission) do
    mission
    |> change(%{
      status: :running,
      started_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for completing a mission successfully.
  """
  def complete_changeset(mission, result \\ %{}) do
    mission
    |> change(%{
      status: :completed,
      completed_at: DateTime.utc_now(),
      result: result
    })
  end

  @doc """
  Changeset for marking a mission as failed.
  """
  def fail_changeset(mission, error) do
    new_retry_count = mission.retry_count + 1

    if new_retry_count >= mission.max_retries do
      # Permanently failed
      mission
      |> change(%{
        status: :failed,
        completed_at: DateTime.utc_now(),
        retry_count: new_retry_count,
        last_error: error
      })
    else
      # Schedule retry with exponential backoff
      backoff_seconds = calculate_backoff(new_retry_count)
      next_retry = DateTime.add(DateTime.utc_now(), backoff_seconds, :second)

      mission
      |> change(%{
        status: :pending,
        retry_count: new_retry_count,
        next_retry_at: next_retry,
        last_error: error,
        scheduled_at: nil,
        started_at: nil
      })
    end
  end

  @doc """
  Changeset for canceling a mission.
  """
  def cancel_changeset(mission, reason \\ "Canceled by user") do
    mission
    |> change(%{
      status: :canceled,
      completed_at: DateTime.utc_now(),
      last_error: reason
    })
  end

  # Calculate exponential backoff: 2^retry * 30 seconds, max 1 hour
  defp calculate_backoff(retry_count) do
    base = 30
    max_backoff = 3600
    min(trunc(:math.pow(2, retry_count) * base), max_backoff)
  end

  defp validate_deadline(changeset) do
    case get_field(changeset, :deadline) do
      nil ->
        changeset

      deadline ->
        if DateTime.compare(deadline, DateTime.utc_now()) == :lt do
          add_error(changeset, :deadline, "must be in the future")
        else
          changeset
        end
    end
  end
end
