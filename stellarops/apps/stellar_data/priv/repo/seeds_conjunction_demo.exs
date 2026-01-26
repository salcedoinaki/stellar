# Demo conjunction data with positions for testing
# Run with: mix run priv/repo/seeds_conjunction_demo.exs

alias StellarData.Repo
alias StellarData.{SpaceObjects, Conjunctions, Satellites}

IO.puts("Seeding demo conjunction data with positions...")

# Get existing space objects (just use first two)
all_objects = SpaceObjects.list_space_objects(limit: 10)

if length(all_objects) < 2 do
  IO.puts("ERROR: Need at least 2 space objects in the database")
  System.halt(1)
end

[primary, secondary | _] = all_objects

IO.puts("Using objects:")
IO.puts("  Primary: #{primary.name} (#{primary.norad_id})")
IO.puts("  Secondary: #{secondary.name} (#{secondary.norad_id})")

# Delete existing demo conjunctions
Repo.delete_all(Conjunctions.Conjunction)

# Create conjunctions with different severities and positions
conjunctions = [
  %{
    primary_object_id: primary.id,
    secondary_object_id: secondary.id,
    tca: DateTime.utc_now() |> DateTime.add(3600, :second),  # 1 hour from now
    miss_distance_m: 450.0,
    relative_velocity_ms: 14500.0,
    collision_probability: 0.0001,  # 0.01% - CRITICAL
    status: :predicted,
    data_source: "demo_seed",
    # ISS approximate position in orbit (ECI coordinates in km)
    primary_position_x_km: 6800.5,
    primary_position_y_km: 500.2,
    primary_position_z_km: 200.1,
    # Debris very close by
    secondary_position_x_km: 6800.95,
    secondary_position_y_km: 500.2,
    secondary_position_z_km: 200.1
  },
  %{
    primary_object_id: primary.id,
    secondary_object_id: secondary.id,
    tca: DateTime.utc_now() |> DateTime.add(7200, :second),  # 2 hours from now
    miss_distance_m: 850.0,
    relative_velocity_ms: 12800.0,
    collision_probability: 0.00005,  # 0.005% - HIGH
    status: :predicted,
    data_source: "demo_seed",
    primary_position_x_km: -3200.8,
    primary_position_y_km: 5800.3,
    primary_position_z_km: -1200.5,
    secondary_position_x_km: -3201.5,
    secondary_position_y_km: 5800.3,
    secondary_position_z_km: -1200.5
  },
  %{
    primary_object_id: primary.id,
    secondary_object_id: secondary.id,
    tca: DateTime.utc_now() |> DateTime.add(14400, :second),  # 4 hours from now
    miss_distance_m: 1500.0,
    relative_velocity_ms: 11200.0,
    collision_probability: 0.000002,  # 0.0002% - MEDIUM
    status: :monitoring,
    data_source: "demo_seed",
    primary_position_x_km: 1200.4,
    primary_position_y_km: -6500.1,
    primary_position_z_km: 800.9,
    secondary_position_x_km: 1201.9,
    secondary_position_y_km: -6500.1,
    secondary_position_z_km: 800.9
  }
]

Enum.each(conjunctions, fn attrs ->
  case Conjunctions.create_conjunction(attrs) do
    {:ok, conj} ->
      IO.puts("✓ Created #{conj.severity} conjunction: #{conj.id}")
      IO.puts("  TCA: #{conj.tca}")
      IO.puts("  Miss distance: #{conj.miss_distance_m} m")
      IO.puts("  Collision probability: #{conj.collision_probability}")
      IO.puts("  Primary position: (#{conj.primary_position_x_km}, #{conj.primary_position_y_km}, #{conj.primary_position_z_km}) km")
      IO.puts("  Secondary position: (#{conj.secondary_position_x_km}, #{conj.secondary_position_y_km}, #{conj.secondary_position_z_km}) km")
    {:error, changeset} ->
      IO.puts("✗ Failed to create conjunction")
      IO.inspect(changeset.errors)
  end
end)

IO.puts("\nDemo data seeded successfully!")
IO.puts("Refresh your browser to see the conjunctions with position data.")
