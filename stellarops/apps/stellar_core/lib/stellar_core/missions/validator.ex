defmodule StellarCore.Missions.Validator do
  @moduledoc """
  Mission parameter validation.

  Validates mission parameters before execution:
  - Resource requirements (energy, memory, bandwidth)
  - Satellite availability and health
  - Ground station availability (for downlink missions)
  - Time constraints (deadlines, contact windows)
  """

  alias StellarCore.Satellite
  alias StellarData.Satellites
  alias StellarData.GroundStations
  alias StellarData.Missions.Mission

  @type validation_result :: :ok | {:error, [validation_error()]}
  @type validation_error :: {atom(), String.t()}

  @doc """
  Validates a mission before scheduling.

  ## Parameters
    - mission: The Mission struct to validate
    - opts: Options
      - `:strict` - If true, perform stricter validation (default: false)

  ## Returns
    - :ok if validation passes
    - {:error, errors} list of validation errors
  """
  @spec validate(Mission.t(), keyword()) :: validation_result()
  def validate(%Mission{} = mission, opts \\ []) do
    errors =
      []
      |> validate_satellite_exists(mission)
      |> validate_satellite_resources(mission, opts)
      |> validate_deadline(mission)
      |> validate_type_specific(mission)
      |> validate_priority_deadline(mission)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Validates if a mission can be executed now.

  More strict than `validate/2` - checks real-time satellite state.
  """
  @spec validate_for_execution(Mission.t()) :: validation_result()
  def validate_for_execution(%Mission{} = mission) do
    errors =
      []
      |> validate_satellite_exists(mission)
      |> validate_satellite_state(mission)
      |> validate_realtime_resources(mission)
      |> validate_type_specific(mission)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Quick check if satellite has enough resources for a mission.
  """
  @spec has_resources?(String.t(), Mission.t()) :: boolean()
  def has_resources?(satellite_id, mission) do
    case Satellite.get_state(satellite_id) do
      {:ok, state} ->
        state.energy >= mission.required_energy and
          (100.0 - state.memory_used) >= mission.required_memory

      {:error, _} ->
        false
    end
  end

  # Private validation functions

  defp validate_satellite_exists(errors, mission) do
    case Satellites.get_satellite(mission.satellite_id) do
      nil ->
        [{:satellite_id, "Satellite '#{mission.satellite_id}' not found"} | errors]

      satellite ->
        if satellite.active do
          errors
        else
          [{:satellite_id, "Satellite '#{mission.satellite_id}' is not active"} | errors]
        end
    end
  end

  defp validate_satellite_resources(errors, mission, opts) do
    strict = Keyword.get(opts, :strict, false)

    case Satellites.get_satellite(mission.satellite_id) do
      nil ->
        errors

      satellite ->
        errors
        |> check_energy_requirement(satellite, mission, strict)
        |> check_memory_requirement(satellite, mission, strict)
    end
  end

  defp check_energy_requirement(errors, satellite, mission, strict) do
    # In strict mode, satellite must have 2x the required energy
    multiplier = if strict, do: 2.0, else: 1.0
    required = mission.required_energy * multiplier

    if satellite.energy >= required do
      errors
    else
      msg =
        if strict do
          "Insufficient energy. Requires #{required}%, satellite has #{satellite.energy}% (strict mode requires 2x buffer)"
        else
          "Insufficient energy. Requires #{mission.required_energy}%, satellite has #{satellite.energy}%"
        end

      [{:required_energy, msg} | errors]
    end
  end

  defp check_memory_requirement(errors, satellite, mission, _strict) do
    available_memory = 100.0 - satellite.memory_used

    if available_memory >= mission.required_memory do
      errors
    else
      [{:required_memory, "Insufficient memory. Requires #{mission.required_memory}%, only #{available_memory}% available"} | errors]
    end
  end

  defp validate_satellite_state(errors, mission) do
    case Satellite.get_state(mission.satellite_id) do
      {:ok, state} ->
        case state.mode do
          :nominal ->
            errors

          :safe ->
            [{:satellite_mode, "Satellite is in safe mode, only critical missions allowed"} | errors]

          :survival ->
            [{:satellite_mode, "Satellite is in survival mode, no missions allowed"} | errors]
        end

      {:error, :not_found} ->
        [{:satellite_id, "Satellite '#{mission.satellite_id}' is not running"} | errors]
    end
  end

  defp validate_realtime_resources(errors, mission) do
    case Satellite.get_state(mission.satellite_id) do
      {:ok, state} ->
        errors
        |> check_realtime_energy(state, mission)
        |> check_realtime_memory(state, mission)

      {:error, _} ->
        errors
    end
  end

  defp check_realtime_energy(errors, state, mission) do
    if state.energy >= mission.required_energy do
      errors
    else
      [{:required_energy, "Real-time energy check failed. Current: #{state.energy}%, Required: #{mission.required_energy}%"} | errors]
    end
  end

  defp check_realtime_memory(errors, state, mission) do
    available = 100.0 - state.memory_used

    if available >= mission.required_memory do
      errors
    else
      [{:required_memory, "Real-time memory check failed. Available: #{available}%, Required: #{mission.required_memory}%"} | errors]
    end
  end

  defp validate_deadline(errors, mission) do
    case mission.deadline do
      nil ->
        errors

      deadline ->
        now = DateTime.utc_now()

        cond do
          DateTime.compare(deadline, now) == :lt ->
            [{:deadline, "Deadline has already passed"} | errors]

          DateTime.diff(deadline, now, :minute) < 5 ->
            [{:deadline, "Deadline is less than 5 minutes away, may not complete in time"} | errors]

          true ->
            errors
        end
    end
  end

  defp validate_priority_deadline(errors, mission) do
    # Critical missions should have reasonable deadlines
    case {mission.priority, mission.deadline} do
      {:critical, nil} ->
        [{:deadline, "Critical missions should have a deadline"} | errors]

      {:critical, deadline} ->
        # Critical missions shouldn't have deadlines more than 24 hours out
        max_deadline = DateTime.add(DateTime.utc_now(), 24, :hour)

        if DateTime.compare(deadline, max_deadline) == :gt do
          [{:deadline, "Critical mission deadline is more than 24 hours away, consider lower priority"} | errors]
        else
          errors
        end

      _ ->
        errors
    end
  end

  defp validate_type_specific(errors, mission) do
    case mission.type do
      "downlink" -> validate_downlink_mission(errors, mission)
      "imaging" -> validate_imaging_mission(errors, mission)
      "orbit_adjust" -> validate_orbit_adjust_mission(errors, mission)
      _ -> errors
    end
  end

  defp validate_downlink_mission(errors, mission) do
    # Downlink missions need a ground station
    case mission.ground_station_id do
      nil ->
        [{:ground_station_id, "Downlink missions require a ground station"} | errors]

      gs_id ->
        case GroundStations.get_ground_station(gs_id) do
          nil ->
            [{:ground_station_id, "Ground station '#{gs_id}' not found"} | errors]

          gs ->
            if gs.status == :online do
              errors
            else
              [{:ground_station_id, "Ground station '#{gs.name}' is not online"} | errors]
            end
        end
    end
  end

  defp validate_imaging_mission(errors, mission) do
    # Imaging missions need target coordinates in payload
    case mission.payload do
      %{"target_lat" => lat, "target_lon" => lon}
      when is_number(lat) and is_number(lon) ->
        errors
        |> validate_coordinates(lat, lon)

      _ ->
        [{:payload, "Imaging missions require target_lat and target_lon in payload"} | errors]
    end
  end

  defp validate_coordinates(errors, lat, lon) do
    errors =
      if lat >= -90 and lat <= 90 do
        errors
      else
        [{:payload, "target_lat must be between -90 and 90"} | errors]
      end

    if lon >= -180 and lon <= 180 do
      errors
    else
      [{:payload, "target_lon must be between -180 and 180"} | errors]
    end
  end

  defp validate_orbit_adjust_mission(errors, mission) do
    # Orbit adjust missions have higher energy requirements
    if mission.required_energy >= 20.0 do
      errors
    else
      [{:required_energy, "Orbit adjustment missions typically require at least 20% energy"} | errors]
    end
  end
end
