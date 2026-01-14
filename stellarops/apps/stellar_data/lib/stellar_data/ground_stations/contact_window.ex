defmodule StellarData.GroundStations.ContactWindow do
  @moduledoc """
  Ecto schema representing a satellite-ground station contact window.

  A contact window defines when a satellite can communicate with a ground station,
  based on orbital geometry (when the satellite is above the horizon from the
  ground station's perspective).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :scheduled | :active | :completed | :missed

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "contact_windows" do
    field :satellite_id, :string

    # Time window
    field :aos, :utc_datetime_usec       # Acquisition of Signal
    field :los, :utc_datetime_usec       # Loss of Signal
    field :tca, :utc_datetime_usec       # Time of Closest Approach (max elevation)

    # Pass characteristics
    field :max_elevation, :float          # Maximum elevation in degrees
    field :aos_azimuth, :float            # Azimuth at AOS
    field :los_azimuth, :float            # Azimuth at LOS
    field :duration_seconds, :integer     # Pass duration

    # Capacity allocation
    field :allocated_bandwidth, :float, default: 0.0  # Mbps allocated
    field :data_transferred, :float, default: 0.0     # MB transferred

    # Status
    field :status, Ecto.Enum,
      values: [:scheduled, :active, :completed, :missed],
      default: :scheduled

    belongs_to :ground_station, StellarData.GroundStations.GroundStation

    timestamps()
  end

  @required_fields [:satellite_id, :ground_station_id, :aos, :los]
  @optional_fields [
    :tca,
    :max_elevation,
    :aos_azimuth,
    :los_azimuth,
    :duration_seconds,
    :allocated_bandwidth,
    :data_transferred,
    :status
  ]

  @doc """
  Creates a changeset for a new contact window.
  """
  def changeset(window, attrs) do
    window
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:max_elevation, greater_than_or_equal_to: 0, less_than_or_equal_to: 90)
    |> validate_number(:aos_azimuth, greater_than_or_equal_to: 0, less_than: 360)
    |> validate_number(:los_azimuth, greater_than_or_equal_to: 0, less_than: 360)
    |> validate_number(:duration_seconds, greater_than: 0)
    |> validate_number(:allocated_bandwidth, greater_than_or_equal_to: 0)
    |> validate_window_times()
    |> calculate_duration()
  end

  @doc """
  Allocates bandwidth for this contact window.
  """
  def allocate_changeset(window, bandwidth_mbps) do
    window
    |> change(%{allocated_bandwidth: bandwidth_mbps})
    |> validate_number(:allocated_bandwidth, greater_than_or_equal_to: 0)
  end

  @doc """
  Marks the window as active (currently in use).
  """
  def activate_changeset(window) do
    window
    |> change(%{status: :active})
  end

  @doc """
  Marks the window as completed with data transfer stats.
  """
  def complete_changeset(window, data_transferred_mb) do
    window
    |> change(%{
      status: :completed,
      data_transferred: data_transferred_mb
    })
  end

  defp validate_window_times(changeset) do
    aos = get_field(changeset, :aos)
    los = get_field(changeset, :los)

    cond do
      is_nil(aos) or is_nil(los) ->
        changeset

      DateTime.compare(los, aos) != :gt ->
        add_error(changeset, :los, "must be after AOS")

      true ->
        changeset
    end
  end

  defp calculate_duration(changeset) do
    aos = get_field(changeset, :aos)
    los = get_field(changeset, :los)

    if aos && los && is_nil(get_field(changeset, :duration_seconds)) do
      duration = DateTime.diff(los, aos, :second)
      put_change(changeset, :duration_seconds, duration)
    else
      changeset
    end
  end
end
