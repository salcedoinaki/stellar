# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside your Docker container:
#     docker compose -f docker-compose.dev.yml run --rm backend mix run apps/stellar_data/priv/repo/seeds.exs

alias StellarData.{Satellites, Telemetry, Commands}

IO.puts("🛰️  Seeding StellarOps database...")

# Create seed satellites
satellites = [
  %{
    id: "SAT-001",
    name: "Alpha Sentinel",
    mode: :nominal,
    energy: 95.5,
    memory_used: 128.0,
    position_x: 6871.0,
    position_y: 0.0,
    position_z: 0.0,
    active: true,
    launched_at: ~U[2025-01-15 10:00:00.000000Z]
  },
  %{
    id: "SAT-002",
    name: "Beta Observer",
    mode: :nominal,
    energy: 88.2,
    memory_used: 256.0,
    position_x: 0.0,
    position_y: 7071.0,
    position_z: 0.0,
    active: true,
    launched_at: ~U[2025-03-20 14:30:00.000000Z]
  },
  %{
    id: "SAT-003",
    name: "Gamma Scanner",
    mode: :safe,
    energy: 45.0,
    memory_used: 512.0,
    position_x: -4850.0,
    position_y: 4850.0,
    position_z: 0.0,
    active: true,
    launched_at: ~U[2025-06-01 08:15:00.000000Z]
  },
  %{
    id: "SAT-004",
    name: "Delta Relay",
    mode: :nominal,
    energy: 100.0,
    memory_used: 64.0,
    position_x: 0.0,
    position_y: 0.0,
    position_z: 6871.0,
    active: true,
    launched_at: ~U[2025-08-10 16:45:00.000000Z]
  },
  %{
    id: "SAT-005",
    name: "Epsilon Beacon",
    mode: :survival,
    energy: 12.3,
    memory_used: 1024.0,
    position_x: 3435.5,
    position_y: 3435.5,
    position_z: 3435.5,
    active: true,
    launched_at: ~U[2024-11-25 22:00:00.000000Z]
  }
]

for sat_attrs <- satellites do
  case Satellites.create_satellite(sat_attrs) do
    {:ok, satellite} ->
      IO.puts("  ✓ Created satellite: #{satellite.id} (#{satellite.name})")

    {:error, changeset} ->
      IO.puts("  ✗ Failed to create satellite: #{sat_attrs.id}")
      IO.inspect(changeset.errors)
  end
end

# Create sample telemetry events
IO.puts("\n📊 Creating sample telemetry events...")

telemetry_events = [
  {"SAT-001", "mode_change", %{from: "safe", to: "nominal"}},
  {"SAT-001", "energy_update", %{old_value: 90.0, new_value: 95.5}},
  {"SAT-002", "memory_warning", %{usage_percent: 65.0, threshold: 60.0}},
  {"SAT-003", "mode_change", %{from: "nominal", to: "safe", reason: "low_energy"}},
  {"SAT-005", "mode_change", %{from: "safe", to: "survival", reason: "critical_energy"}},
  {"SAT-005", "system_alert", %{type: "battery_critical", level: 12.3}}
]

for {sat_id, event_type, data} <- telemetry_events do
  case Telemetry.record_event(sat_id, event_type, data) do
    {:ok, _event} ->
      IO.puts("  ✓ Recorded event: #{event_type} for #{sat_id}")

    {:error, changeset} ->
      IO.puts("  ✗ Failed to record event: #{event_type} for #{sat_id}")
      IO.inspect(changeset.errors)
  end
end

# Create sample commands
IO.puts("\n🎯 Creating sample commands...")

commands = [
  {"SAT-001", "capture_image", %{target: "earth", resolution: "high"}, [priority: 50]},
  {"SAT-002", "transmit_data", %{destination: "ground_station_1"}, [priority: 30]},
  {"SAT-003", "recharge_battery", %{}, [priority: 80]},
  {"SAT-004", "relay_signal", %{source: "SAT-003", destination: "ground_station_2"}, [priority: 40]},
  {"SAT-005", "emergency_shutdown", %{subsystems: ["imaging", "comms"]}, [priority: 100]}
]

for {sat_id, cmd_type, params, opts} <- commands do
  case Commands.create_command(sat_id, cmd_type, params, opts) do
    {:ok, command} ->
      IO.puts("  ✓ Created command: #{cmd_type} for #{sat_id} (priority: #{command.priority})")

    {:error, changeset} ->
      IO.puts("  ✗ Failed to create command: #{cmd_type} for #{sat_id}")
      IO.inspect(changeset.errors)
  end
end

IO.puts("\n✅ Database seeding complete!")
IO.puts("   #{length(satellites)} satellites")
IO.puts("   #{length(telemetry_events)} telemetry events")
IO.puts("   #{length(commands)} commands")
