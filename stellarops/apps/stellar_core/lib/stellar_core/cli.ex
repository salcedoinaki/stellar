defmodule StellarCore.CLI do
  @moduledoc """
  Command-line interface for StellarOps console interaction.

  This module provides all commands for managing the satellite constellation
  via IEx (Interactive Elixir) shell.

  ## Usage

  Start the console:
      docker compose -f docker-compose.dev.yml exec backend iex -S mix

  Then use commands like:
      StellarCore.CLI.satellites()
      StellarCore.CLI.create_satellite("SAT-001", "My Satellite")
  """

  require Logger

  alias StellarCore.{Satellite, Alarms, TLEIngester}
  alias StellarCore.SSA.ConjunctionDetector
  alias StellarCore.SSA.COAPlanner
  alias StellarCore.TLEIngester.CelesTrakClient
  alias StellarCore.Commands.CommandQueue
  alias StellarData.{Satellites, Commands, Missions, GroundStations, SpaceObjects, Conjunctions, COAs}
  alias StellarData.COA, as: COAContext

  # ============================================================================
  # SATELLITE COMMANDS
  # ============================================================================

  @doc """
  Lists all satellites in the constellation.

  ## Example
      iex> StellarCore.CLI.satellites()
  """
  def satellites do
    sats = Satellites.list_satellites()
    
    IO.puts("\n=== SATELLITES (#{length(sats)}) ===\n")
    
    if sats == [] do
      IO.puts("  No satellites found. Create one with:")
      IO.puts("  StellarCore.CLI.create_satellite(\"SAT-001\", \"My Satellite\")")
    else
      Enum.each(sats, fn sat ->
        # Check if GenServer is actually running
        genserver_running = Satellite.alive?(sat.id)
        status = if sat.active && genserver_running, do: "✓ ACTIVE", else: "✗ INACTIVE"
        IO.puts("  [#{sat.id}] #{sat.name} - #{status}")
        IO.puts("      Mode: #{sat.mode || "unknown"}, Energy: #{sat.energy || 0}%")
        IO.puts("")
      end)
    end
    
    :ok
  end

  @doc """
  Shows detailed information about a specific satellite.

  ## Example
      iex> StellarCore.CLI.satellite("SAT-001")
  """
  def satellite(id) do
    case Satellites.get_satellite(id) do
      nil ->
        IO.puts("\n  ✗ Satellite '#{id}' not found.\n")
        {:error, :not_found}

      sat ->
        IO.puts("\n=== SATELLITE: #{sat.name} ===\n")
        IO.puts("  ID:          #{sat.id}")
        IO.puts("  Name:        #{sat.name}")
        IO.puts("  Active:      #{sat.active}")
        IO.puts("  Mode:        #{sat.mode || "unknown"}")
        IO.puts("  Energy:      #{sat.energy || 0}%")
        IO.puts("  Memory:      #{sat.memory_used || 0} MB")
        IO.puts("  NORAD ID:    #{sat.norad_id || "N/A"}")
        IO.puts("  Created:     #{sat.inserted_at}")
        IO.puts("")
        
        # Show runtime state if the satellite is running
        case Satellite.get_state(id) do
          {:ok, state} ->
            IO.puts("  --- Runtime State (GenServer) ---")
            IO.puts("  Mode:        #{state.mode}")
            IO.puts("  Energy:      #{state.energy}%")
            IO.puts("  Memory:      #{state.memory_used} MB")
            {x, y, z} = state.position
            IO.puts("  Position:    (#{x}, #{y}, #{z})")
            IO.puts("")
          _ -> :ok
        end
        
        {:ok, sat}
    end
  end

  @doc """
  Creates a new satellite.

  ## Parameters
    - id: Unique identifier (e.g., "SAT-001")
    - name: Human-readable name
    - opts: Optional keyword list with :norad_id, :orbit_regime, etc.

  ## Example
      iex> StellarCore.CLI.create_satellite("SAT-001", "Sentinel Alpha")
      iex> StellarCore.CLI.create_satellite("SAT-002", "Sentinel Beta", norad_id: 12345)
  """
  def create_satellite(id, name, opts \\ []) do
    attrs = %{
      id: id,
      name: name,
      active: true,
      mode: "nominal",
      energy: 100.0,
      norad_id: Keyword.get(opts, :norad_id),
      orbit_regime: Keyword.get(opts, :orbit_regime, "LEO")
    }

    case Satellites.create_satellite(attrs) do
      {:ok, sat} ->
        IO.puts("\n  ✓ Satellite '#{sat.name}' (#{sat.id}) created successfully.\n")
        
        # Start the satellite GenServer
        case Satellite.start(id) do
          {:ok, _pid} ->
            IO.puts("  ✓ Satellite GenServer started.\n")
          {:error, reason} ->
            IO.puts("  ! Warning: Could not start GenServer: #{inspect(reason)}\n")
        end
        
        {:ok, sat}

      {:error, changeset} ->
        IO.puts("\n  ✗ Failed to create satellite:")
        Enum.each(changeset.errors, fn {field, {msg, _}} ->
          IO.puts("    - #{field}: #{msg}")
        end)
        IO.puts("")
        {:error, changeset}
    end
  end

  @doc """
  Deletes a satellite.

  ## Example
      iex> StellarCore.CLI.delete_satellite("SAT-001")
  """
  def delete_satellite(id) do
    # Stop the GenServer first
    Satellite.stop(id)
    
    case Satellites.get_satellite(id) do
      nil ->
        IO.puts("\n  ✗ Satellite '#{id}' not found.\n")
        {:error, :not_found}

      sat ->
        case Satellites.delete_satellite(sat) do
          {:ok, _} ->
            IO.puts("\n  ✓ Satellite '#{id}' deleted successfully.\n")
            :ok
          {:error, reason} ->
            IO.puts("\n  ✗ Failed to delete satellite: #{inspect(reason)}\n")
            {:error, reason}
        end
    end
  end

  @doc """
  Starts a satellite's runtime GenServer.

  ## Example
      iex> StellarCore.CLI.start_satellite("SAT-001")
  """
  def start_satellite(id) do
    case Satellite.start(id) do
      {:ok, pid} ->
        IO.puts("\n  ✓ Satellite '#{id}' started (PID: #{inspect(pid)}).\n")
        {:ok, pid}
      {:error, :already_exists} ->
        IO.puts("\n  ! Satellite '#{id}' is already running.\n")
        {:error, :already_exists}
      {:error, reason} ->
        IO.puts("\n  ✗ Failed to start satellite: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  @doc """
  Stops a satellite's runtime GenServer.

  ## Example
      iex> StellarCore.CLI.stop_satellite("SAT-001")
  """
  def stop_satellite(id) do
    case Satellite.stop(id) do
      :ok ->
        IO.puts("\n  ✓ Satellite '#{id}' stopped.\n")
        :ok
      {:error, :not_found} ->
        IO.puts("\n  ! Satellite '#{id}' is not running.\n")
        {:error, :not_found}
    end
  end

  @doc """
  Updates a satellite's mode.

  ## Modes
    - "nominal" - Normal operations
    - "safe" - Safe mode (reduced operations)
    - "eclipse" - Eclipse mode (power saving)
    - "maneuver" - Maneuvering

  ## Example
      iex> StellarCore.CLI.set_mode("SAT-001", "safe")
  """
  def set_mode(satellite_id, mode) when is_binary(mode) do
    mode_atom = String.to_existing_atom(mode)
    case Satellite.set_mode(satellite_id, mode_atom) do
      {:ok, state} ->
        IO.puts("\n  ✓ Satellite '#{satellite_id}' mode changed to '#{mode}'.\n")
        {:ok, state}
      {:error, reason} ->
        IO.puts("\n  ✗ Failed to update mode: #{inspect(reason)}\n")
        {:error, reason}
    end
  rescue
    ArgumentError ->
      IO.puts("\n  ✗ Invalid mode '#{mode}'. Valid modes: nominal, safe, survival\n")
      {:error, :invalid_mode}
  end

  @doc """
  Updates a satellite's energy level.

  ## Example
      iex> StellarCore.CLI.set_energy("SAT-001", 85.5)
  """
  def set_energy(satellite_id, energy) when is_number(energy) do
    case Satellite.update_energy(satellite_id, energy - get_current_energy(satellite_id)) do
      {:ok, state} ->
        IO.puts("\n  ✓ Satellite '#{satellite_id}' energy set to #{energy}%.\n")
        {:ok, state}
      {:error, reason} ->
        IO.puts("\n  ✗ Failed to update energy: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  defp get_current_energy(satellite_id) do
    case Satellite.get_state(satellite_id) do
      {:ok, state} -> state.energy
      _ -> 0
    end
  end

  # ============================================================================
  # COMMAND QUEUE COMMANDS
  # ============================================================================

  @doc """
  Lists commands for a satellite.

  ## Example
      iex> StellarCore.CLI.commands("SAT-001")
      iex> StellarCore.CLI.commands("SAT-001", status: :pending, limit: 10)
  """
  def commands(satellite_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    status = Keyword.get(opts, :status)
    
    cmds = Commands.get_command_history(satellite_id, [limit: limit, status: status])
    
    IO.puts("\n=== COMMANDS FOR #{satellite_id} (#{length(cmds)}) ===\n")
    
    if cmds == [] do
      IO.puts("  No commands found.")
    else
      Enum.each(cmds, fn cmd ->
        status_icon = case cmd.status do
          :queued -> "◌"
          :pending -> "◌"
          :acknowledged -> "◎"
          :executing -> "▶"
          :completed -> "✓"
          :failed -> "✗"
          :cancelled -> "⊘"
          _ -> "?"
        end
        IO.puts("  [#{status_icon}] #{cmd.id} - #{cmd.command_type} (#{cmd.status})")
        IO.puts("      Priority: #{cmd.priority}, Created: #{cmd.inserted_at}")
      end)
    end
    
    IO.puts("")
    :ok
  end

  @doc """
  Queues a new command for a satellite.

  ## Command Types
    - "set_mode" - Change operational mode
    - "collect_telemetry" - Force telemetry collection
    - "download_data" - Schedule data download
    - "update_orbit" - Orbital adjustment
    - "reboot" - Satellite reboot

  ## Example
      iex> StellarCore.CLI.queue_command("SAT-001", "set_mode", %{"mode" => "safe"})
      iex> StellarCore.CLI.queue_command("SAT-001", "collect_telemetry", %{}, priority: 100)
  """
  def queue_command(satellite_id, command_type, params \\ %{}, opts \\ []) do
    priority = Keyword.get(opts, :priority, 50)
    
    case CommandQueue.queue_command(satellite_id, command_type, params, priority: priority) do
      {:ok, command} ->
        IO.puts("\n  ✓ Command '#{command_type}' queued for #{satellite_id}.")
        IO.puts("    Command ID: #{command.id}")
        IO.puts("    Priority: #{priority}")
        IO.puts("")
        {:ok, command}
      {:error, reason} ->
        IO.puts("\n  ✗ Failed to queue command: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  @doc """
  Cancels a pending command.

  ## Example
      iex> StellarCore.CLI.cancel_command("cmd-uuid-here")
  """
  def cancel_command(command_id) do
    case CommandQueue.cancel_command(command_id) do
      {:ok, command} ->
        IO.puts("\n  ✓ Command '#{command_id}' cancelled.\n")
        {:ok, command}
      {:error, reason} ->
        IO.puts("\n  ✗ Failed to cancel command: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  # ============================================================================
  # MISSION COMMANDS
  # ============================================================================

  @doc """
  Lists all missions.

  ## Example
      iex> StellarCore.CLI.missions()
      iex> StellarCore.CLI.missions(status: :pending)
  """
  def missions(opts \\ []) do
    status = Keyword.get(opts, :status)
    satellite_id = Keyword.get(opts, :satellite_id)
    
    filters = %{}
    filters = if status, do: Map.put(filters, :status, status), else: filters
    filters = if satellite_id, do: Map.put(filters, :satellite_id, satellite_id), else: filters
    
    mission_list = if filters == %{}, do: Missions.list_missions(), else: Missions.list_missions(filters)
    
    IO.puts("\n=== MISSIONS (#{length(mission_list)}) ===\n")
    
    if mission_list == [] do
      IO.puts("  No missions found.")
    else
      Enum.each(mission_list, fn m ->
        status_icon = case m.status do
          :completed -> "✓"
          :failed -> "✗"
          :pending -> "◌"
          :executing -> "▶"
          :cancelled -> "⊘"
          _ -> "?"
        end
        IO.puts("  [#{status_icon}] #{m.id}")
        IO.puts("      Name: #{m.name}")
        IO.puts("      Type: #{m.type}, Satellite: #{m.satellite_id}")
        IO.puts("      Priority: #{m.priority}, Status: #{m.status}")
        IO.puts("")
      end)
    end
    
    :ok
  end

  @doc """
  Creates a new mission.

  ## Mission Types
    - "imaging" - Earth observation
    - "communication" - Data relay
    - "maintenance" - System maintenance
    - "maneuver" - Orbital maneuver
    - "downlink" - Data downlink

  ## Example
      iex> StellarCore.CLI.create_mission("SAT-001", "imaging", "Photo Survey Alpha")
      iex> StellarCore.CLI.create_mission("SAT-001", "maneuver", "Orbit Raise", priority: :high)
  """
  def create_mission(satellite_id, type, name, opts \\ []) do
    attrs = %{
      satellite_id: satellite_id,
      type: type,
      name: name,
      priority: Keyword.get(opts, :priority, :normal),
      status: :pending,
      parameters: Keyword.get(opts, :parameters, %{}),
      deadline: Keyword.get(opts, :deadline)
    }

    case Missions.create_mission(attrs) do
      {:ok, mission} ->
        IO.puts("\n  ✓ Mission '#{name}' created.")
        IO.puts("    Mission ID: #{mission.id}")
        IO.puts("    Type: #{type}, Satellite: #{satellite_id}")
        IO.puts("")
        {:ok, mission}
      {:error, changeset} ->
        IO.puts("\n  ✗ Failed to create mission:")
        Enum.each(changeset.errors, fn {field, {msg, _}} ->
          IO.puts("    - #{field}: #{msg}")
        end)
        IO.puts("")
        {:error, changeset}
    end
  end

  @doc """
  Cancels a mission.

  Accepts either a mission UUID or mission name.

  ## Examples
      iex> StellarCore.CLI.cancel_mission("62947aed-fea2-44c4-9cd8-1d55b5196fe2")
      iex> StellarCore.CLI.cancel_mission("Test Y")
  """
  def cancel_mission(identifier) do
    case Missions.get_mission_by_id_or_name(identifier) do
      nil ->
        IO.puts("\n  ✗ Mission '#{identifier}' not found.\n")
        {:error, :not_found}
      mission ->
        case Missions.update_mission(mission, %{status: :canceled}) do
          {:ok, m} ->
            IO.puts("\n  ✓ Mission '#{mission.name}' (#{mission.id}) canceled.\n")
            {:ok, m}
          {:error, reason} ->
            IO.puts("\n  ✗ Failed to cancel mission: #{inspect(reason)}\n")
            {:error, reason}
        end
    end
  end

  # ============================================================================
  # GROUND STATION COMMANDS
  # ============================================================================

  @doc """
  Lists all ground stations.

  ## Example
      iex> StellarCore.CLI.ground_stations()
  """
  def ground_stations do
    stations = GroundStations.list_ground_stations()
    
    IO.puts("\n=== GROUND STATIONS (#{length(stations)}) ===\n")
    
    if stations == [] do
      IO.puts("  No ground stations found. Create one with:")
      IO.puts("  StellarCore.CLI.create_ground_station(\"GS-DENVER\", \"Denver\", 39.7392, -104.9903)")
    else
      Enum.each(stations, fn gs ->
        status_icon = case gs.status do
          :online -> "✓"
          :offline -> "✗"
          :maintenance -> "⚠"
          _ -> "?"
        end
        IO.puts("  [#{status_icon}] #{gs.code} - #{gs.name} (#{gs.status})")
        IO.puts("      Location: #{gs.latitude}°, #{gs.longitude}°")
        IO.puts("      Bandwidth: #{gs.bandwidth_mbps} Mbps")
        IO.puts("")
      end)
    end
    
    :ok
  end

  @doc """
  Creates a new ground station.

  ## Example
      iex> StellarCore.CLI.create_ground_station("GS-TOKYO", "Tokyo Station", 35.6762, 139.6503)
  """
  def create_ground_station(code, name, latitude, longitude, opts \\ []) do
    attrs = %{
      code: code,
      name: name,
      latitude: latitude,
      longitude: longitude,
      status: :online,
      bandwidth_mbps: Keyword.get(opts, :bandwidth_mbps, 100.0),
      min_elevation_deg: Keyword.get(opts, :min_elevation_deg, 10.0)
    }

    case GroundStations.create_ground_station(attrs) do
      {:ok, gs} ->
        IO.puts("\n  ✓ Ground station '#{gs.name}' (#{gs.code}) created.\n")
        {:ok, gs}
      {:error, changeset} ->
        IO.puts("\n  ✗ Failed to create ground station:")
        Enum.each(changeset.errors, fn {field, {msg, _}} ->
          IO.puts("    - #{field}: #{msg}")
        end)
        IO.puts("")
        {:error, changeset}
    end
  end

  @doc """
  Sets a ground station's status.

  ## Example
      iex> StellarCore.CLI.set_station_status("GS-DENVER", :maintenance)
  """
  def set_station_status(code, status) when status in [:online, :offline, :maintenance] do
    case GroundStations.get_ground_station_by_code(code) do
      nil ->
        IO.puts("\n  ✗ Ground station '#{code}' not found.\n")
        {:error, :not_found}
      station ->
        case GroundStations.set_station_status(station, status) do
          {:ok, gs} ->
            IO.puts("\n  ✓ Ground station '#{code}' set to #{status}.\n")
            {:ok, gs}
          {:error, reason} ->
            IO.puts("\n  ✗ Failed to update status: #{inspect(reason)}\n")
            {:error, reason}
        end
    end
  end

  # ============================================================================
  # SPACE SITUATIONAL AWARENESS (SSA) COMMANDS
  # ============================================================================

  @doc """
  Lists space objects in the catalog.

  ## Example
      iex> StellarCore.CLI.space_objects()
      iex> StellarCore.CLI.space_objects(object_type: "debris", limit: 10)
  """
  def space_objects(opts \\ []) do
    objects = SpaceObjects.list_objects(opts)
    limit = Keyword.get(opts, :limit, 20)
    
    displayed = Enum.take(objects, limit)
    
    IO.puts("\n=== SPACE OBJECTS (showing #{length(displayed)} of #{length(objects)}) ===\n")
    
    if objects == [] do
      IO.puts("  No space objects found.")
    else
      Enum.each(displayed, fn obj ->
        threat_icon = case obj.threat_level do
          :critical -> "🔴"
          :high -> "⚠️"
          :medium -> "⚡"
          :low -> "○"
          :none -> "✓"
          _ -> "?"
        end
        IO.puts("  [#{threat_icon}] #{obj.norad_id || obj.id} - #{obj.name || "Unknown"}")
        IO.puts("      Type: #{obj.object_type}, Regime: #{obj.orbit_type || "N/A"}")
        IO.puts("      Threat: #{obj.threat_level || "unknown"}")
        IO.puts("")
      end)
    end
    
    :ok
  end

  @doc """
  Shows details of a specific space object.

  ## Example
      iex> StellarCore.CLI.space_object(25544)  # ISS NORAD ID
  """
  def space_object(norad_id) when is_integer(norad_id) do
    case SpaceObjects.get_object_by_norad_id(norad_id) do
      nil ->
        IO.puts("\n  ✗ Space object with NORAD ID #{norad_id} not found.\n")
        {:error, :not_found}
      obj ->
        IO.puts("\n=== SPACE OBJECT: #{obj.name || "Unknown"} ===\n")
        IO.puts("  NORAD ID:     #{obj.norad_id}")
        IO.puts("  Name:         #{obj.name}")
        IO.puts("  Type:         #{obj.object_type}")
        IO.puts("  Regime:       #{obj.orbit_type || "N/A"}")
        IO.puts("  Threat Level: #{obj.threat_level || "unknown"}")
        IO.puts("  TLE Epoch:    #{obj.tle_epoch || "N/A"}")
        IO.puts("")
        {:ok, obj}
    end
  end

  @doc """
  Lists current conjunctions (collision threats).

  ## Example
      iex> StellarCore.CLI.conjunctions()
      iex> StellarCore.CLI.conjunctions(severity: :critical)
  """
  def conjunctions(opts \\ []) do
    conjs = Conjunctions.list_conjunctions(opts)
    
    IO.puts("\n=== CONJUNCTIONS (#{length(conjs)}) ===\n")
    
    if conjs == [] do
      IO.puts("  No active conjunctions. System is clear.")
    else
      Enum.each(conjs, fn c ->
        severity_icon = case c.severity do
          :critical -> "🔴"
          :high -> "🟠"
          :medium -> "🟡"
          :low -> "🟢"
          _ -> "⚪"
        end
        IO.puts("  [#{severity_icon}] #{c.id}")
        IO.puts("      Primary: #{c.primary_object_id}, Secondary: #{c.secondary_object_id}")
        IO.puts("      TCA: #{c.tca}")
        IO.puts("      Miss Distance: #{format_distance_km(c.miss_distance_m)} km")
        IO.puts("      Collision Prob: #{format_probability(c.collision_probability)}")
        IO.puts("      Status: #{c.status}")
        IO.puts("")
      end)
    end
    
    :ok
  end

  defp format_probability(nil), do: "N/A"
  defp format_probability(prob) when is_float(prob), do: "#{Float.round(prob * 100, 4)}%"
  defp format_probability(prob), do: inspect(prob)

  defp format_distance_km(nil), do: "N/A"
  defp format_distance_km(meters) when is_number(meters), do: Float.round(meters / 1000.0, 3)
  defp format_distance_km(value), do: inspect(value)

  @doc """
  Triggers an immediate conjunction screening cycle.

  ## Example
      iex> StellarCore.CLI.screen_conjunctions()
  """
  def screen_conjunctions do
    IO.puts("\n  ▶ Starting conjunction screening...")
    
    case ConjunctionDetector.detect_now() do
      {:ok, results} ->
        IO.puts("  ✓ Screening complete.")
        IO.puts("    New conjunctions: #{results[:new_count] || 0}")
        IO.puts("    Updated conjunctions: #{results[:updated_count] || 0}")
        IO.puts("")
        {:ok, results}
      {:error, reason} ->
        IO.puts("  ✗ Screening failed: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  # ============================================================================
  # TLE INGESTION COMMANDS
  # ============================================================================

  @doc """
  Fetches TLE data from CelesTrak and updates space objects.

  ## Categories
    :stations    - Space stations (ISS, Tiangong, etc.)
    :active      - All active satellites
    :weather     - Weather satellites
    :noaa        - NOAA satellites
    :goes        - GOES satellites
    :debris      - Tracked debris

  ## Examples
      iex> StellarCore.CLI.fetch_tles()
      iex> StellarCore.CLI.fetch_tles(:stations)
      iex> StellarCore.CLI.fetch_tles(:active)
  """
  def fetch_tles(category \\ :stations) do
    IO.puts("\n  ▶ Fetching TLEs from CelesTrak (#{category})...")
    
    # Ensure HTTP client is started
    :inets.start()
    :ssl.start()
    
    # Call CelesTrak directly without GenServer
    with {:ok, tle_text} <- CelesTrakClient.fetch(category),
         {:ok, tles} <- StellarCore.TLEIngester.TLEParser.parse_multi(tle_text) do
      
      # Update each space object
      count = Enum.reduce(tles, 0, fn tle, acc ->
        case SpaceObjects.get_object_by_norad_id(tle.norad_id) do
          nil -> acc  # Object not in our DB, skip
          obj ->
            attrs = %{
              tle_line1: tle.line1,
              tle_line2: tle.line2,
              tle_epoch: tle.epoch,
              tle_updated_at: DateTime.utc_now(),
              inclination_deg: tle.inclination,
              eccentricity: tle.eccentricity,
              raan_deg: tle.raan,
              arg_perigee_deg: tle.arg_perigee,
              mean_anomaly_deg: tle.mean_anomaly,
              mean_motion: tle.mean_motion,
              bstar_drag: tle.bstar
            }
            case SpaceObjects.update_object(obj, attrs) do
              {:ok, _} -> acc + 1
              {:error, _} -> acc
            end
        end
      end)
      
      IO.puts("  ✓ Successfully updated #{count} space objects with TLE data.")
      IO.puts("    (#{length(tles)} TLEs fetched, #{count} matched objects in DB)")
      IO.puts("")
      {:ok, count}
    else
      {:error, reason} ->
        IO.puts("  ✗ Failed to fetch TLEs: #{inspect(reason)}")
        IO.puts("")
        {:error, reason}
    end
  end

  @doc """
  Fetches TLE for a specific space object by NORAD ID and updates it.

  ## Example
      iex> StellarCore.CLI.refresh_tle(25544)  # ISS
  """
  def refresh_tle(norad_id) when is_integer(norad_id) do
    IO.puts("\n  ▶ Fetching TLE for NORAD ID #{norad_id}...")
    
    # Ensure HTTP client is started
    :inets.start()
    :ssl.start()
    
    case CelesTrakClient.fetch_by_norad_id(norad_id) do
      {:ok, tle_text} ->
        case StellarCore.TLEIngester.TLEParser.parse_multi(tle_text) do
          {:ok, [tle | _]} ->
            # Update the space object with the TLE data
            case SpaceObjects.get_object_by_norad_id(norad_id) do
              nil ->
                IO.puts("  ✗ Space object with NORAD ID #{norad_id} not found in database.")
                IO.puts("")
                {:error, :not_found}
              obj ->
                attrs = %{
                  tle_line1: tle.line1,
                  tle_line2: tle.line2,
                  tle_epoch: tle.epoch,
                  tle_updated_at: DateTime.utc_now(),
                  inclination_deg: tle.inclination,
                  eccentricity: tle.eccentricity,
                  raan_deg: tle.raan,
                  arg_perigee_deg: tle.arg_perigee,
                  mean_anomaly_deg: tle.mean_anomaly,
                  mean_motion: tle.mean_motion,
                  bstar_drag: tle.bstar
                }
                case SpaceObjects.update_object(obj, attrs) do
                  {:ok, updated} ->
                    IO.puts("  ✓ Updated TLE for #{updated.name || norad_id}")
                    IO.puts("    Epoch: #{tle.epoch}")
                    IO.puts("    Inclination: #{Float.round(tle.inclination, 4)}°")
                    IO.puts("    Eccentricity: #{tle.eccentricity}")
                    IO.puts("    Mean Motion: #{Float.round(tle.mean_motion, 8)} rev/day")
                    IO.puts("")
                    {:ok, updated}
                  {:error, changeset} ->
                    IO.puts("  ✗ Failed to update: #{inspect(changeset.errors)}")
                    IO.puts("")
                    {:error, changeset}
                end
            end
          {:ok, []} ->
            IO.puts("  ✗ No TLE data returned for NORAD ID #{norad_id}")
            IO.puts("")
            {:error, :no_data}
          {:error, reason} ->
            IO.puts("  ✗ Failed to parse TLE: #{inspect(reason)}")
            IO.puts("")
            {:error, reason}
        end
      {:error, reason} ->
        IO.puts("  ✗ Failed to fetch TLE: #{inspect(reason)}")
        IO.puts("")
        {:error, reason}
    end
  end

  @doc """
  Shows TLE freshness statistics for all space objects.

  ## Example
      iex> StellarCore.CLI.tle_status()
  """
  def tle_status do
    objects = SpaceObjects.list_space_objects([])
    
    total = length(objects)
    with_tle = Enum.count(objects, & &1.tle_line1)
    without_tle = total - with_tle
    
    stale_threshold = DateTime.add(DateTime.utc_now(), -7, :day)
    stale = Enum.count(objects, fn obj ->
      obj.tle_updated_at && DateTime.compare(obj.tle_updated_at, stale_threshold) == :lt
    end)
    
    fresh = with_tle - stale
    
    IO.puts("\n=== TLE STATUS ===\n")
    IO.puts("  Total space objects: #{total}")
    IO.puts("  With TLE data:       #{with_tle} (#{percentage(with_tle, total)})")
    IO.puts("  Without TLE data:    #{without_tle} (#{percentage(without_tle, total)})")
    IO.puts("  Fresh (< 7 days):    #{fresh}")
    IO.puts("  Stale (> 7 days):    #{stale}")
    IO.puts("")
    
    :ok
  end

  defp percentage(_, 0), do: "N/A"
  defp percentage(count, total), do: "#{Float.round(count / total * 100, 1)}%"

  @doc """
  Debug: Test raw TLE fetch from CelesTrak.
  Shows the raw response to diagnose parsing issues.

  ## Example
      iex> StellarCore.CLI.debug_tle_fetch(:stations)
  """
  def debug_tle_fetch(category \\ :stations) do
    IO.puts("\n=== DEBUG TLE FETCH ===\n")
    IO.puts("  Category: #{category}")
    
    # Ensure HTTP client is started
    :inets.start()
    :ssl.start()
    
    case CelesTrakClient.fetch(category) do
      {:ok, body} ->
        IO.puts("  Response size: #{byte_size(body)} bytes")
        IO.puts("  Response type: #{if is_binary(body), do: "binary", else: "list"}")
        
        # Show first few lines
        lines = body |> String.split(~r/\r?\n/) |> Enum.take(9)
        IO.puts("  First #{length(lines)} lines:")
        IO.puts("")
        Enum.each(lines, fn line -> IO.puts("    #{line}") end)
        IO.puts("")
        
        # Try parsing
        case StellarCore.TLEIngester.TLEParser.parse_multi(body) do
          {:ok, tles} ->
            IO.puts("  Parsed #{length(tles)} TLEs")
            if length(tles) > 0 do
              tle = hd(tles)
              IO.puts("  First TLE: #{tle.name} (NORAD #{tle.norad_id})")
            end
          {:error, reason} ->
            IO.puts("  Parse error: #{inspect(reason)}")
        end
        
        {:ok, body}
        
      {:error, reason} ->
        IO.puts("  Fetch error: #{inspect(reason)}")
        {:error, reason}
    end
  end
  @doc """
  Shows details of a specific conjunction.

  ## Example
      iex> StellarCore.CLI.conjunction("conj-uuid")
  """
  def conjunction(id) do
    case Conjunctions.get_conjunction(id) do
      nil ->
        IO.puts("\n  ✗ Conjunction '#{id}' not found.\n")
        {:error, :not_found}
      c ->
        IO.puts("\n=== CONJUNCTION: #{id} ===\n")
        IO.puts("  Primary Object:   #{c.primary_object_id}")
        IO.puts("  Secondary Object: #{c.secondary_object_id}")
        IO.puts("  TCA:              #{c.tca}")
        IO.puts("  Miss Distance:    #{format_distance_km(c.miss_distance_m)} km")
        IO.puts("  Collision Prob:   #{format_probability(c.collision_probability)}")
        IO.puts("  Relative Velocity: #{c.relative_velocity_km_s || "N/A"} km/s")
        IO.puts("  Severity:         #{c.severity}")
        IO.puts("  Status:           #{c.status}")
        IO.puts("")
        {:ok, c}
    end
  end

  # ============================================================================
  # COURSE OF ACTION (COA) COMMANDS
  # ============================================================================

  @doc """
  Lists courses of action for collision avoidance.

  ## Example
      iex> StellarCore.CLI.coas()
      iex> StellarCore.CLI.coas(status: :pending)
  """
  def coas(opts \\ []) do
    coa_list = COAContext.list_coas(opts)
    
    IO.puts("\n=== COURSES OF ACTION (#{length(coa_list)}) ===\n")
    
    if coa_list == [] do
      IO.puts("  No COAs found.")
    else
      Enum.each(coa_list, fn coa ->
        status_icon = case coa.status do
          :approved -> "✓"
          :rejected -> "✗"
          :proposed -> "◌"
          :selected -> "★"
          :executing -> "▶"
          :completed -> "✓"
          _ -> "?"
        end
        delta_v = coa.delta_v_ms || 0.0
        fuel = coa.fuel_cost_kg || 0.0
        IO.puts("  [#{status_icon}] #{coa.id}")
        IO.puts("      Type: #{coa.coa_type}, Title: #{coa.title}")
        IO.puts("      Conjunction: #{coa.conjunction_id}")
        IO.puts("      Delta-V: #{Float.round(delta_v, 3)} m/s, Fuel: #{Float.round(fuel, 2)} kg")
        IO.puts("      Status: #{coa.status}")
        IO.puts("")
      end)
    end
    
    :ok
  end

  @doc """
  Generates COAs for a conjunction.

  ## Example
      iex> StellarCore.CLI.generate_coas("conj-uuid")
  """
  def generate_coas(conjunction_id) do
    IO.puts("\n  ▶ Generating COAs for conjunction #{conjunction_id}...")
    
    case COAPlanner.generate_coas(conjunction_id) do
      {:ok, coa_list} ->
        IO.puts("  ✓ Generated #{length(coa_list)} COAs.")
        Enum.each(coa_list, fn coa ->
          delta_v = coa.delta_v_ms || 0.0
          risk = coa.risk_if_no_action || 0.0
          IO.puts("    - #{coa.coa_type}: ΔV=#{Float.round(delta_v, 3)} m/s, Risk=#{Float.round(risk * 100, 1)}%")
        end)
        IO.puts("")
        {:ok, coa_list}
      {:error, reason} ->
        IO.puts("  ✗ Failed to generate COAs: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  @doc """
  Approves a COA for execution.

  ## Example
      iex> StellarCore.CLI.approve_coa("coa-uuid", "operator@stellarops.com")
  """
  def approve_coa(coa_id, approved_by) do
    case COAContext.get_coa(coa_id) do
      nil ->
        IO.puts("\n  ✗ Failed to approve COA: not found\n")
        {:error, :not_found}
      coa ->
        case COAContext.approve_coa(coa, approved_by) do
          {:ok, updated} ->
            IO.puts("\n  ✓ COA '#{coa_id}' approved by #{approved_by}.\n")
            {:ok, updated}
          {:error, reason} ->
            IO.puts("\n  ✗ Failed to approve COA: #{inspect(reason)}\n")
            {:error, reason}
        end
    end
  end

  @doc """
  Selects a COA for execution (creates mission).

  ## Example
      iex> StellarCore.CLI.select_coa("coa-uuid", "operator@stellarops.com")
  """
  def select_coa(coa_id, selected_by) do
    case COAContext.get_coa(coa_id) do
      nil ->
        IO.puts("\n  ✗ Failed to select COA: not found\n")
        {:error, :not_found}
      coa ->
        case COAContext.approve_coa(coa, selected_by) do
          {:ok, updated} ->
            IO.puts("\n  ✓ COA '#{coa_id}' selected for execution by #{selected_by}.\n")
            {:ok, updated}
          {:error, reason} ->
            IO.puts("\n  ✗ Failed to select COA: #{inspect(reason)}\n")
            {:error, reason}
        end
    end
  end

  @doc """
  Rejects a COA.

  ## Example
      iex> StellarCore.CLI.reject_coa("coa-uuid", "operator@stellarops.com", "Insufficient fuel")
  """
  def reject_coa(coa_id, rejected_by, notes \\ nil) do
    case COAContext.get_coa(coa_id) do
      nil ->
        IO.puts("\n  ✗ Failed to reject COA: not found\n")
        {:error, :not_found}
      coa ->
        case COAContext.reject_coa(coa, rejected_by, notes) do
          {:ok, updated} ->
            IO.puts("\n  ✓ COA '#{coa_id}' rejected.\n")
            {:ok, updated}
          {:error, reason} ->
            IO.puts("\n  ✗ Failed to reject COA: #{inspect(reason)}\n")
            {:error, reason}
        end
    end
  end

  # ============================================================================
  # ALARM COMMANDS
  # ============================================================================

  @doc """
  Lists all active alarms.

  ## Example
      iex> StellarCore.CLI.alarms()
  """
  def alarms do
    alarm_list = Alarms.list_alarms()
    
    active = Enum.filter(alarm_list, &(&1.status == :active))
    acknowledged = Enum.filter(alarm_list, &(&1.status == :acknowledged))
    
    IO.puts("\n=== ALARMS ===\n")
    IO.puts("  Active: #{length(active)}, Acknowledged: #{length(acknowledged)}")
    IO.puts("")
    
    if active == [] do
      IO.puts("  ✓ No active alarms. System healthy.")
    else
      Enum.each(active, fn alarm ->
        severity_icon = case alarm.severity do
          :critical -> "🔴"
          :major -> "🟠"
          :minor -> "🟡"
          :warning -> "⚠️"
          :info -> "ℹ️"
          _ -> "?"
        end
        IO.puts("  [#{severity_icon}] #{alarm.id}")
        IO.puts("      Type: #{alarm.type}")
        IO.puts("      Message: #{alarm.message}")
        IO.puts("      Source: #{alarm.source}")
        IO.puts("      Created: #{alarm.created_at}")
        IO.puts("")
      end)
    end
    
    :ok
  end

  @doc """
  Raises a new alarm.

  ## Severity Levels
    - :critical - Immediate action required
    - :major - Action required soon
    - :minor - Attention needed
    - :warning - Potential issue
    - :info - Informational

  ## Example
      iex> StellarCore.CLI.raise_alarm("system_test", :info, "Test alarm", "console")
  """
  def raise_alarm(type, severity, message, source, details \\ %{}) do
    case Alarms.raise_alarm(type, severity, message, source, details) do
      {:ok, alarm} ->
        IO.puts("\n  ✓ Alarm raised: #{alarm.id}\n")
        {:ok, alarm}
      {:error, reason} ->
        IO.puts("\n  ✗ Failed to raise alarm: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  @doc """
  Acknowledges an alarm.

  ## Example
      iex> StellarCore.CLI.ack_alarm("alarm-uuid", "operator@stellarops.com")
  """
  def ack_alarm(alarm_id, acknowledged_by \\ "console") do
    case Alarms.acknowledge_alarm(alarm_id, acknowledged_by) do
      {:ok, alarm} ->
        IO.puts("\n  ✓ Alarm '#{alarm_id}' acknowledged.\n")
        {:ok, alarm}
      {:error, reason} ->
        IO.puts("\n  ✗ Failed to acknowledge alarm: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  @doc """
  Resolves an alarm.

  ## Example
      iex> StellarCore.CLI.resolve_alarm("alarm-uuid")
  """
  def resolve_alarm(alarm_id) do
    case Alarms.resolve_alarm(alarm_id) do
      {:ok, alarm} ->
        IO.puts("\n  ✓ Alarm '#{alarm_id}' resolved.\n")
        {:ok, alarm}
      {:error, reason} ->
        IO.puts("\n  ✗ Failed to resolve alarm: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  # ============================================================================
  # SYSTEM STATUS COMMANDS
  # ============================================================================

  @doc """
  Shows system status overview.

  ## Example
      iex> StellarCore.CLI.status()
  """
  def status do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("                    STELLAROPS STATUS")
    IO.puts(String.duplicate("=", 60) <> "\n")
    
    # Satellites
    sat_count = Satellite.count()
    db_sats = length(Satellites.list_satellites())
    IO.puts("  SATELLITES")
    IO.puts("    Running GenServers: #{sat_count}")
    IO.puts("    Database records:   #{db_sats}")
    IO.puts("")
    
    # Ground Stations
    stations = GroundStations.list_ground_stations()
    online = Enum.count(stations, &(&1.status == :online))
    IO.puts("  GROUND STATIONS")
    IO.puts("    Total: #{length(stations)}, Online: #{online}")
    IO.puts("")
    
    # Conjunctions
    conjs = Conjunctions.list_conjunctions([])
    active_conjs = Enum.count(conjs, &(&1.status in [:detected, :analyzing]))
    critical = Enum.count(conjs, &(&1.severity == :critical))
    IO.puts("  CONJUNCTIONS")
    IO.puts("    Active: #{active_conjs}, Critical: #{critical}")
    IO.puts("")
    
    # Alarms
    alarm_list = Alarms.list_alarms()
    active_alarms = Enum.count(alarm_list, &(&1.status == :active))
    IO.puts("  ALARMS")
    IO.puts("    Active: #{active_alarms}")
    IO.puts("")
    
    # Missions
    pending_missions = length(Missions.get_pending_missions())
    IO.puts("  MISSIONS")
    IO.puts("    Pending: #{pending_missions}")
    IO.puts("")
    
    IO.puts(String.duplicate("=", 60))
    IO.puts("")
    
    :ok
  end

  @doc """
  Shows detailed health check of all services.

  ## Example
      iex> StellarCore.CLI.health()
  """
  def health do
    IO.puts("\n=== SYSTEM HEALTH ===\n")
    
    # Check database
    db_status = try do
      StellarData.Repo.query!("SELECT 1")
      "✓ Connected"
    rescue
      _ -> "✗ Disconnected"
    end
    IO.puts("  Database:       #{db_status}")
    
    # Check satellite supervisor
    sat_sup = if Process.whereis(StellarCore.Satellite.Supervisor), do: "✓ Running", else: "✗ Down"
    IO.puts("  Sat Supervisor: #{sat_sup}")
    
    # Check conjunction detector (check both possible modules)
    conj_det = cond do
      Process.whereis(StellarCore.SSA.ConjunctionDetector) -> "✓ Running"
      Process.whereis(StellarCore.ConjunctionDetector) -> "✓ Running"
      true -> "✗ Down"
    end
    IO.puts("  Conj Detector:  #{conj_det}")
    
    # Check command queue
    cmd_queue = if Process.whereis(StellarCore.Commands.CommandQueue), do: "✓ Running", else: "✗ Down"
    IO.puts("  Command Queue:  #{cmd_queue}")
    
    # Check alarms
    alarms_svc = if Process.whereis(StellarCore.Alarms), do: "✓ Running", else: "✗ Down"
    IO.puts("  Alarms:         #{alarms_svc}")
    
    IO.puts("")
    :ok
  end

  # ============================================================================
  # HELP COMMANDS
  # ============================================================================

  @doc """
  Shows available commands grouped by category.

  ## Example
      iex> StellarCore.CLI.help()
  """
  def help do
    IO.puts("""

    ╔══════════════════════════════════════════════════════════════════════╗
    ║                      STELLAROPS CLI COMMANDS                        ║
    ╚══════════════════════════════════════════════════════════════════════╝

    All commands are prefixed with: StellarCore.CLI.

    ─────────────────────────────────────────────────────────────────────────
    SATELLITES
    ─────────────────────────────────────────────────────────────────────────
      satellites()                          List all satellites
      satellite(id)                         Show satellite details
      create_satellite(id, name, opts)      Create a new satellite
      delete_satellite(id)                  Delete a satellite
      start_satellite(id)                   Start satellite GenServer
      stop_satellite(id)                    Stop satellite GenServer
      set_mode(id, mode)                    Change satellite mode
      set_energy(id, energy)                Set satellite energy level

    ─────────────────────────────────────────────────────────────────────────
    COMMANDS
    ─────────────────────────────────────────────────────────────────────────
      commands(satellite_id, opts)          List commands for satellite
      queue_command(sat_id, type, params)   Queue a new command
      cancel_command(command_id)            Cancel a pending command

    ─────────────────────────────────────────────────────────────────────────
    MISSIONS
    ─────────────────────────────────────────────────────────────────────────
      missions(opts)                        List all missions
      create_mission(sat_id, type, name)    Create a new mission
      cancel_mission(mission_id)            Cancel a mission

    ─────────────────────────────────────────────────────────────────────────
    GROUND STATIONS
    ─────────────────────────────────────────────────────────────────────────
      ground_stations()                     List all ground stations
      create_ground_station(code, name, lat, lon)  Create ground station
      set_station_status(code, status)      Set station status

    ─────────────────────────────────────────────────────────────────────────
    SPACE SITUATIONAL AWARENESS (SSA)
    ─────────────────────────────────────────────────────────────────────────
      space_objects(opts)                   List space objects
      space_object(norad_id)                Show space object details
      conjunctions(opts)                    List conjunctions
      conjunction(id)                       Show conjunction details
      screen_conjunctions()                 Trigger conjunction screening

    ─────────────────────────────────────────────────────────────────────────
    TLE DATA
    ─────────────────────────────────────────────────────────────────────────
      fetch_tles(category)                  Fetch TLEs from CelesTrak
                                            Categories: :stations, :active,
                                            :weather, :debris
      refresh_tle(norad_id)                 Refresh TLE for one object
      tle_status()                          Show TLE freshness stats

    ─────────────────────────────────────────────────────────────────────────
    COURSES OF ACTION (COA)
    ─────────────────────────────────────────────────────────────────────────
      coas(opts)                            List all COAs
      generate_coas(conjunction_id)         Generate COAs for conjunction
      approve_coa(id, approved_by)          Approve a COA
      select_coa(id, selected_by)           Select COA for execution
      reject_coa(id, rejected_by, notes)    Reject a COA

    ─────────────────────────────────────────────────────────────────────────
    ALARMS
    ─────────────────────────────────────────────────────────────────────────
      alarms()                              List all alarms
      raise_alarm(type, severity, msg, src) Raise a new alarm
      ack_alarm(id, by)                     Acknowledge an alarm
      resolve_alarm(id)                     Resolve an alarm

    ─────────────────────────────────────────────────────────────────────────
    SYSTEM
    ─────────────────────────────────────────────────────────────────────────
      status()                              Show system status overview
      health()                              Show service health check
      help()                                Show this help message
      debug()                               Show current debug mode
      debug(true/false)                     Enable/disable debug logging
      quiet()                               Disable debug logging (alias)
      verbose()                             Enable debug logging (alias)

    ─────────────────────────────────────────────────────────────────────────
    TIPS
    ─────────────────────────────────────────────────────────────────────────
      • Use tab completion in IEx for command discovery
      • Commands return {:ok, result} or {:error, reason} tuples
      • Use h(StellarCore.CLI.command_name) for detailed help
      • Pipe output to IO.inspect for debugging: satellites() |> IO.inspect

    """)
    
    :ok
  end

  # ============================================================================
  # DEBUG MODE COMMANDS
  # ============================================================================

  @doc """
  Shows current debug mode status.

  ## Example
      iex> StellarCore.CLI.debug()
  """
  def debug do
    current_level = Logger.level()
    is_debug = current_level == :debug
    
    IO.puts("\n=== DEBUG MODE ===")
    IO.puts("  Current log level: #{current_level}")
    IO.puts("  Debug output: #{if is_debug, do: "✓ ENABLED", else: "✗ DISABLED"}")
    IO.puts("")
    IO.puts("  Use debug(true) to enable debug logging")
    IO.puts("  Use debug(false) or quiet() to disable")
    IO.puts("")
    
    {:ok, is_debug}
  end

  @doc """
  Enables or disables debug logging.

  When debug mode is enabled, you'll see detailed database queries,
  GenServer messages, and other low-level system activity.

  When disabled (default for demos), only info, warning, and error
  messages are shown.

  ## Examples
      iex> StellarCore.CLI.debug(true)   # Enable debug output
      iex> StellarCore.CLI.debug(false)  # Disable debug output
  """
  def debug(enabled) when is_boolean(enabled) do
    new_level = if enabled, do: :debug, else: :info
    Logger.configure(level: new_level)
    
    if enabled do
      IO.puts("\n  ✓ Debug mode ENABLED - showing all log output")
      IO.puts("    Use debug(false) or quiet() to disable\n")
    else
      IO.puts("\n  ✓ Debug mode DISABLED - clean console output")
      IO.puts("    Use debug(true) or verbose() to enable\n")
    end
    
    {:ok, enabled}
  end

  @doc """
  Disables debug logging (alias for debug(false)).

  Useful for demos and presentations where you want clean output.

  ## Example
      iex> StellarCore.CLI.quiet()
  """
  def quiet do
    debug(false)
  end

  @doc """
  Enables debug logging (alias for debug(true)).

  Useful for troubleshooting and development.

  ## Example
      iex> StellarCore.CLI.verbose()
  """
  def verbose do
    debug(true)
  end

  # ============================================================================
  # DEMO / SEED COMMANDS
  # ============================================================================

  @doc """
  Seeds demo conjunction events for presentation purposes.

  Creates realistic conjunction scenarios with different severities
  that can be used to demonstrate COA generation and workflows.

  ## Example
      iex> StellarCore.CLI.seed_demo_conjunctions()
  """
  def seed_demo_conjunctions do
    IO.puts("\n  ▶ Creating demo conjunctions...\n")

    # Get space objects from the database
    objects = SpaceObjects.list_objects(limit: 10)
    
    if length(objects) < 2 do
      IO.puts("  ✗ Need at least 2 space objects in database.")
      IO.puts("    Run the seeds first or create space objects.")
      {:error, :insufficient_objects}
    else
      now = DateTime.utc_now()
      
      # Get first few objects for conjunctions
      [obj1, obj2 | rest] = objects
      obj3 = List.first(rest) || obj2
      obj4 = Enum.at(rest, 1) || obj1

      # Get satellites if available
      sats = Satellites.list_satellites()
      sat1 = List.first(sats)
      sat2 = Enum.at(sats, 1)

      demo_conjunctions = [
        # Critical - immediate action required
        %{
          primary_object_id: obj1.id,
          secondary_object_id: obj2.id,
          satellite_id: sat1 && sat1.id,
          tca: DateTime.add(now, 4 * 3600, :second),
          miss_distance_m: 450.0,
          relative_velocity_ms: 14200.0,
          collision_probability: 0.00035,
          severity: :critical,
          status: :active,
          data_source: "DEMO-18SDS",
          notes: "Demo: Critical conjunction requiring immediate COA"
        },
        # High - action likely needed
        %{
          primary_object_id: obj2.id,
          secondary_object_id: obj3.id,
          satellite_id: sat2 && sat2.id,
          tca: DateTime.add(now, 12 * 3600, :second),
          miss_distance_m: 2800.0,
          relative_velocity_ms: 11500.0,
          collision_probability: 0.00012,
          severity: :high,
          status: :active,
          data_source: "DEMO-LeoLabs",
          notes: "Demo: High-severity approach"
        },
        # Medium - monitoring
        %{
          primary_object_id: obj1.id,
          secondary_object_id: obj4.id,
          satellite_id: nil,
          tca: DateTime.add(now, 36 * 3600, :second),
          miss_distance_m: 7500.0,
          relative_velocity_ms: 9800.0,
          collision_probability: 0.000045,
          severity: :medium,
          status: :monitoring,
          data_source: "DEMO-18SDS",
          notes: "Demo: Medium-risk being monitored"
        },
        # Low - tracking only
        %{
          primary_object_id: obj3.id,
          secondary_object_id: obj4.id,
          satellite_id: nil,
          tca: DateTime.add(now, 72 * 3600, :second),
          miss_distance_m: 15000.0,
          relative_velocity_ms: 7200.0,
          collision_probability: 0.000008,
          severity: :low,
          status: :predicted,
          data_source: "DEMO-18SDS",
          notes: "Demo: Low-risk tracking"
        }
      ]

      created = Enum.reduce(demo_conjunctions, 0, fn attrs, acc ->
        case Conjunctions.create_conjunction(attrs) do
          {:ok, conj} ->
            severity_icon = case conj.severity do
              :critical -> "🔴"
              :high -> "🟠"
              :medium -> "🟡"
              :low -> "🟢"
              _ -> "⚪"
            end
            IO.puts("  #{severity_icon} Created #{conj.severity} conjunction: #{conj.id}")
            IO.puts("      TCA: #{conj.tca}")
            IO.puts("      Miss Distance: #{Float.round(conj.miss_distance_m / 1000, 2)} km")
            IO.puts("")
            acc + 1
          {:error, changeset} ->
            IO.puts("  ✗ Failed to create conjunction: #{inspect(changeset.errors)}")
            acc
        end
      end)

      IO.puts("  ✓ Created #{created} demo conjunctions.\n")
      IO.puts("  Next steps:")
      IO.puts("    CLI.conjunctions()           - View all conjunctions")
      IO.puts("    CLI.generate_coas(\"<id>\")    - Generate COAs for a conjunction")
      IO.puts("")
      {:ok, created}
    end
  end

  @doc """
  Clears all demo conjunctions (those with DEMO data source).

  ## Example
      iex> StellarCore.CLI.clear_demo_conjunctions()
  """
  def clear_demo_conjunctions do
    IO.puts("\n  ▶ Clearing demo conjunctions...\n")

    conjs = Conjunctions.list_conjunctions()
    demo_conjs = Enum.filter(conjs, fn c -> 
      c.data_source && String.starts_with?(c.data_source, "DEMO") 
    end)

    deleted = Enum.reduce(demo_conjs, 0, fn conj, acc ->
      case Conjunctions.delete_conjunction(conj) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)

    IO.puts("  ✓ Deleted #{deleted} demo conjunctions.\n")
    {:ok, deleted}
  end
end
