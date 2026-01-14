defmodule StellarData.GroundStations.GroundStation do
  @moduledoc """
  Ecto schema representing a ground station.

  Ground stations are used for satellite communication, with:
  - Geographic location
  - Bandwidth capacity
  - Availability windows for downlink scheduling
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :online | :offline | :maintenance

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "ground_stations" do
    field :name, :string
    field :code, :string  # Short identifier, e.g., "SVALBARD", "CANBERRA"
    field :description, :string

    # Geographic location
    field :latitude, :float
    field :longitude, :float
    field :altitude, :float, default: 0.0  # meters above sea level
    field :timezone, :string, default: "UTC"

    # Capabilities
    field :bandwidth_mbps, :float, default: 100.0  # Max bandwidth in Mbps
    field :frequency_band, :string, default: "S"   # S, X, Ka band
    field :min_elevation, :float, default: 5.0     # Minimum elevation angle in degrees
    field :antenna_diameter, :float                 # Antenna diameter in meters

    # Status
    field :status, Ecto.Enum, values: [:online, :offline, :maintenance], default: :online
    field :current_load, :float, default: 0.0      # Current bandwidth usage %

    # Relationships
    has_many :contact_windows, StellarData.GroundStations.ContactWindow

    timestamps()
  end

  @required_fields [:name, :code, :latitude, :longitude]
  @optional_fields [
    :description,
    :altitude,
    :timezone,
    :bandwidth_mbps,
    :frequency_band,
    :min_elevation,
    :antenna_diameter,
    :status,
    :current_load
  ]

  @doc """
  Creates a changeset for a new ground station.
  """
  def changeset(ground_station, attrs) do
    ground_station
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_number(:altitude, greater_than_or_equal_to: 0)
    |> validate_number(:bandwidth_mbps, greater_than: 0)
    |> validate_number(:min_elevation, greater_than_or_equal_to: 0, less_than_or_equal_to: 90)
    |> validate_number(:current_load, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint(:code)
  end

  @doc """
  Updates the ground station status.
  """
  def status_changeset(ground_station, status) do
    ground_station
    |> change(%{status: status})
  end

  @doc """
  Updates the current load percentage.
  """
  def load_changeset(ground_station, load_percent) do
    ground_station
    |> change(%{current_load: load_percent})
    |> validate_number(:current_load, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
