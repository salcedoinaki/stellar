# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside your Docker container:
#     docker compose -f docker-compose.dev.yml run --rm backend mix run apps/stellar_data/priv/repo/seeds.exs

alias StellarData.{Satellites, Telemetry, Commands, SpaceObjects, Conjunctions}

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

# ============================================================================
# SSA (Space Situational Awareness) Data
# ============================================================================

IO.puts("\n🌍 Creating space objects...")

space_objects = [
  %{
    norad_id: 25544,
    name: "ISS (ZARYA)",
    international_designator: "1998-067A",
    object_type: :satellite,
    owner: "NASA/ESA/JAXA/CSA",
    status: :active,
    orbit_type: :leo,
    inclination_deg: 51.64,
    apogee_km: 422.0,
    perigee_km: 418.0,
    period_minutes: 92.9,
    threat_level: :none,
    classification: :unclassified,
    is_protected_asset: true
  },
  %{
    norad_id: 43013,
    name: "COSMOS 2542",
    international_designator: "2017-080A",
    object_type: :satellite,
    owner: "Russia",
    status: :active,
    orbit_type: :leo,
    inclination_deg: 82.4,
    apogee_km: 620.0,
    perigee_km: 610.0,
    period_minutes: 97.0,
    threat_level: :medium,
    classification: :unclassified,
    intel_summary: "Russian inspection satellite with maneuvering capability"
  },
  %{
    norad_id: 40258,
    name: "CZ-2C DEB",
    international_designator: "2014-065C",
    object_type: :debris,
    owner: "China",
    status: :inactive,
    orbit_type: :leo,
    inclination_deg: 97.8,
    apogee_km: 815.0,
    perigee_km: 790.0,
    period_minutes: 101.0,
    threat_level: :low,
    classification: :unclassified
  },
  %{
    norad_id: 39771,
    name: "COSMOS 2499",
    international_designator: "2014-028E",
    object_type: :satellite,
    owner: "Russia",
    status: :active,
    orbit_type: :leo,
    inclination_deg: 65.0,
    apogee_km: 1175.0,
    perigee_km: 1160.0,
    period_minutes: 109.0,
    threat_level: :high,
    classification: :unclassified,
    intel_summary: "Suspected anti-satellite capable spacecraft"
  },
  %{
    norad_id: 26411,
    name: "FENGYUN 1C DEB",
    international_designator: "1999-025APM",
    object_type: :debris,
    owner: "China",
    status: :inactive,
    orbit_type: :sso,
    inclination_deg: 98.6,
    apogee_km: 865.0,
    perigee_km: 855.0,
    period_minutes: 102.0,
    threat_level: :low,
    classification: :unclassified,
    notes: "Debris from 2007 ASAT test"
  },
  %{
    norad_id: 45915,
    name: "STARLINK-1095",
    international_designator: "2020-035B",
    object_type: :satellite,
    owner: "SpaceX",
    status: :active,
    orbit_type: :leo,
    inclination_deg: 53.0,
    apogee_km: 550.0,
    perigee_km: 545.0,
    period_minutes: 95.6,
    threat_level: :none,
    classification: :unclassified
  },
  %{
    norad_id: 48274,
    name: "SHIJIAN-21",
    international_designator: "2021-094A",
    object_type: :satellite,
    owner: "China",
    status: :active,
    orbit_type: :geo,
    inclination_deg: 0.1,
    apogee_km: 35800.0,
    perigee_km: 35780.0,
    period_minutes: 1436.0,
    threat_level: :high,
    classification: :unclassified,
    intel_summary: "Active debris removal demonstrator with potential dual-use capability"
  },
  %{
    norad_id: 49445,
    name: "UNKNOWN OBJECT",
    international_designator: "2021-UNK-001",
    object_type: :unknown,
    owner: "Unknown",
    status: :unknown,
    orbit_type: :heo,
    inclination_deg: 63.4,
    apogee_km: 39200.0,
    perigee_km: 500.0,
    period_minutes: 720.0,
    threat_level: :critical,
    classification: :unclassified,
    intel_summary: "Unidentified object in highly elliptical orbit, monitoring required"
  }
]

created_objects = 
  for obj_attrs <- space_objects do
    case SpaceObjects.create_object(obj_attrs) do
      {:ok, obj} ->
        IO.puts("  ✓ Created space object: #{obj.norad_id} (#{obj.name})")
        obj

      {:error, _changeset} ->
        # Object already exists, fetch it
        case SpaceObjects.get_object_by_norad_id(obj_attrs.norad_id) do
          nil ->
            IO.puts("  ✗ Failed to create/find space object: #{obj_attrs.norad_id}")
            nil
          existing ->
            IO.puts("  ✓ Found existing space object: #{existing.norad_id} (#{existing.name})")
            existing
        end
    end
  end
  |> Enum.reject(&is_nil/1)

# Create conjunctions
IO.puts("\n⚠️  Creating conjunction events...")

# Get some object IDs for conjunctions (need at least 4 objects)
{iss, cosmos_2542, debris1, cosmos_2499} = 
  case created_objects do
    [a, b, c, d | _rest] -> {a, b, c, d}
    _ ->
      IO.puts("  ⚠️  Not enough space objects to create conjunctions, skipping...")
      {nil, nil, nil, nil}
  end

# Get satellite IDs
sat_001 = "SAT-001"
sat_003 = "SAT-003"

now = DateTime.utc_now()

created_conjunctions = 
  if iss != nil and cosmos_2542 != nil and debris1 != nil and cosmos_2499 != nil do
    conjunctions = [
      %{
        primary_object_id: iss.id,
        secondary_object_id: debris1.id,
        satellite_id: nil,
        tca: DateTime.add(now, 2 * 24 * 3600, :second),
        miss_distance_m: 450.0,
        relative_velocity_ms: 14500.0,
        collision_probability: 0.00012,
        severity: :medium,
        status: :predicted,
        data_source: "18SDS"
      },
      %{
        primary_object_id: nil,
        secondary_object_id: cosmos_2542.id,
        satellite_id: sat_001,
        tca: DateTime.add(now, 8 * 3600, :second),
        miss_distance_m: 1200.0,
        relative_velocity_ms: 7800.0,
        collision_probability: 0.000025,
        severity: :low,
        status: :monitoring,
        data_source: "LeoLabs"
      },
      %{
        primary_object_id: nil,
        secondary_object_id: cosmos_2499.id,
        satellite_id: sat_003,
        tca: DateTime.add(now, 4 * 3600, :second),
        miss_distance_m: 180.0,
        relative_velocity_ms: 12300.0,
        collision_probability: 0.0045,
        severity: :critical,
        status: :active,
        data_source: "18SDS",
        notes: "High-priority event - suspected ASAT proximity approach"
      },
      %{
        primary_object_id: iss.id,
        secondary_object_id: cosmos_2499.id,
        satellite_id: nil,
        tca: DateTime.add(now, 36 * 3600, :second),
        miss_distance_m: 2500.0,
        relative_velocity_ms: 9800.0,
        collision_probability: 0.000001,
        severity: :low,
        status: :predicted,
        data_source: "18SDS"
      }
    ]

    for conj_attrs <- conjunctions do
      case Conjunctions.create_conjunction(conj_attrs) do
        {:ok, conj} ->
          IO.puts("  ✓ Created conjunction: #{conj.id} (severity: #{conj.severity})")
          conj

        {:error, changeset} ->
          IO.puts("  ✗ Failed to create conjunction")
          IO.inspect(changeset.errors)
          nil
      end
    end
    |> Enum.reject(&is_nil/1)
  else
    []
  end

IO.puts("\n🔒 SSA data seeding complete!")
IO.puts("   #{length(created_objects)} space objects")
IO.puts("   #{length(created_conjunctions)} conjunctions")
