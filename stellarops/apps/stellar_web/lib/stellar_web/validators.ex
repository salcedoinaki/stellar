defmodule StellarWeb.Validators do
  @moduledoc """
  Input validation module for StellarOps API.
  
  Provides comprehensive validation for:
  - REST API request payloads
  - WebSocket channel messages
  - TLE format validation
  - NORAD ID format
  - Numeric ranges
  
  ## Usage
  
      # Validate satellite creation params
      case Validators.validate_satellite_params(params) do
        {:ok, validated} -> create_satellite(validated)
        {:error, errors} -> render_errors(conn, errors)
      end
  """
  
  @valid_modes ~w(normal safe survival standby)a
  @valid_object_types ~w(satellite debris rocket_body unknown)a
  @valid_classifications ~w(hostile suspicious unknown friendly)a
  @valid_threat_levels ~w(critical high medium low none)a
  @valid_coa_types ~w(retrograde_burn inclination_change phasing_maneuver flyby station_keeping)a
  
  @doc """
  Validate satellite creation/update parameters.
  """
  def validate_satellite_params(params) do
    with {:ok, name} <- validate_string(params, "name", required: true, max_length: 100),
         {:ok, norad_id} <- validate_norad_id(params, "norad_id"),
         {:ok, mode} <- validate_mode(params, "mode"),
         {:ok, energy} <- validate_number(params, "energy", min: 0, max: 100),
         {:ok, memory_used} <- validate_number(params, "memory_used", min: 0) do
      {:ok, %{
        name: name,
        norad_id: norad_id,
        mode: mode,
        energy: energy || 100.0,
        memory_used: memory_used || 0.0
      }}
    end
  end
  
  @doc """
  Validate mode transition request.
  """
  def validate_mode(params, key \\ "mode") do
    case get_param(params, key) do
      nil -> {:ok, nil}
      mode when is_binary(mode) ->
        case parse_mode(mode) do
          nil -> {:error, [{key, "must be one of: #{Enum.join(@valid_modes, ", ")}"}]}
          parsed -> {:ok, parsed}
        end
      mode when is_atom(mode) ->
        if mode in @valid_modes do
          {:ok, mode}
        else
          {:error, [{key, "must be one of: #{Enum.join(@valid_modes, ", ")}"}]}
        end
      _ ->
        {:error, [{key, "must be a string or atom"}]}
    end
  end
  
  @doc """
  Validate energy update request.
  """
  def validate_energy_update(params) do
    with {:ok, delta} <- validate_number(params, "delta", required: true),
         {:ok, _} <- validate_range(delta, -100, 100, "delta") do
      {:ok, %{delta: delta}}
    end
  end
  
  @doc """
  Validate position update request.
  """
  def validate_position_update(params) do
    with {:ok, x} <- validate_number(params, "x", required: true),
         {:ok, y} <- validate_number(params, "y", required: true),
         {:ok, z} <- validate_number(params, "z", required: true) do
      {:ok, %{x: x, y: y, z: z}}
    end
  end
  
  @doc """
  Validate TLE format (Two-Line Element).
  """
  def validate_tle(params) do
    with {:ok, line1} <- validate_tle_line(params, "tle_line1", 1),
         {:ok, line2} <- validate_tle_line(params, "tle_line2", 2) do
      {:ok, %{tle_line1: line1, tle_line2: line2}}
    end
  end
  
  @doc """
  Validate a single TLE line.
  """
  def validate_tle_line(params, key, line_number) do
    case get_param(params, key) do
      nil ->
        {:error, [{key, "is required"}]}
        
      line when is_binary(line) ->
        line = String.trim(line)
        
        cond do
          String.length(line) != 69 ->
            {:error, [{key, "must be exactly 69 characters"}]}
            
          !String.starts_with?(line, "#{line_number} ") ->
            {:error, [{key, "must start with '#{line_number} '"}]}
            
          !valid_tle_checksum?(line) ->
            {:error, [{key, "has invalid checksum"}]}
            
          true ->
            {:ok, line}
        end
        
      _ ->
        {:error, [{key, "must be a string"}]}
    end
  end
  
  @doc """
  Validate NORAD ID format.
  """
  def validate_norad_id(params, key \\ "norad_id") do
    case get_param(params, key) do
      nil ->
        {:ok, nil}
        
      id when is_integer(id) and id > 0 and id < 100_000_000 ->
        {:ok, id}
        
      id when is_binary(id) ->
        case Integer.parse(id) do
          {parsed, ""} when parsed > 0 and parsed < 100_000_000 ->
            {:ok, parsed}
          _ ->
            {:error, [{key, "must be a positive integer less than 100,000,000"}]}
        end
        
      _ ->
        {:error, [{key, "must be a positive integer"}]}
    end
  end
  
  @doc """
  Validate mission parameters.
  """
  def validate_mission_params(params) do
    with {:ok, name} <- validate_string(params, "name", required: true, max_length: 200),
         {:ok, type} <- validate_string(params, "type", required: true),
         {:ok, satellite_id} <- validate_uuid(params, "satellite_id", required: true),
         {:ok, priority} <- validate_integer(params, "priority", min: 1, max: 10),
         {:ok, deadline} <- validate_datetime(params, "deadline"),
         {:ok, required_energy} <- validate_number(params, "required_energy", min: 0),
         {:ok, required_memory} <- validate_number(params, "required_memory", min: 0),
         {:ok, required_bandwidth} <- validate_number(params, "required_bandwidth", min: 0),
         {:ok, payload} <- validate_json(params, "payload") do
      {:ok, %{
        name: name,
        type: type,
        satellite_id: satellite_id,
        priority: priority || 5,
        deadline: deadline,
        required_energy: required_energy || 0,
        required_memory: required_memory || 0,
        required_bandwidth: required_bandwidth || 0,
        payload: payload || %{}
      }}
    end
  end
  
  @doc """
  Validate space object parameters.
  """
  def validate_space_object_params(params) do
    with {:ok, norad_id} <- validate_norad_id(params, "norad_id"),
         {:ok, _} when not is_nil(norad_id) <- {:ok, norad_id} || {:error, [{"norad_id", "is required"}]},
         {:ok, name} <- validate_string(params, "name", required: true, max_length: 100),
         {:ok, object_type} <- validate_enum(params, "object_type", @valid_object_types),
         {:ok, tle} <- validate_tle_optional(params),
         {:ok, intl_designator} <- validate_string(params, "international_designator", max_length: 20),
         {:ok, owner} <- validate_string(params, "owner", max_length: 100),
         {:ok, country_code} <- validate_string(params, "country_code", max_length: 10) do
      {:ok, Map.merge(%{
        norad_id: norad_id,
        name: name,
        object_type: object_type || :unknown,
        international_designator: intl_designator,
        owner: owner,
        country_code: country_code
      }, tle || %{})}
    end
  end
  
  @doc """
  Validate threat classification parameters.
  """
  def validate_threat_classification(params) do
    with {:ok, classification} <- validate_enum(params, "classification", @valid_classifications, required: true),
         {:ok, threat_level} <- validate_enum(params, "threat_level", @valid_threat_levels),
         {:ok, capabilities} <- validate_string_list(params, "capabilities"),
         {:ok, intel_summary} <- validate_string(params, "intel_summary", max_length: 5000),
         {:ok, notes} <- validate_string(params, "notes", max_length: 2000),
         {:ok, confidence} <- validate_enum(params, "confidence_level", ~w(high medium low)a) do
      {:ok, %{
        classification: classification,
        threat_level: threat_level,
        capabilities: capabilities || [],
        intel_summary: intel_summary,
        notes: notes,
        confidence_level: confidence || :medium
      }}
    end
  end
  
  @doc """
  Validate COA selection parameters.
  """
  def validate_coa_selection(params) do
    with {:ok, reason} <- validate_string(params, "reason", max_length: 500) do
      {:ok, %{reason: reason}}
    end
  end
  
  @doc """
  Validate alarm acknowledgment parameters.
  """
  def validate_alarm_acknowledgment(params) do
    with {:ok, notes} <- validate_string(params, "notes", max_length: 1000) do
      {:ok, %{notes: notes}}
    end
  end
  
  @doc """
  Validate conjunction filter parameters.
  """
  def validate_conjunction_filters(params) do
    with {:ok, asset_id} <- validate_uuid(params, "asset_id"),
         {:ok, severity} <- validate_enum(params, "severity", ~w(critical high medium low)a),
         {:ok, status} <- validate_enum(params, "status", ~w(active monitoring resolved expired)a),
         {:ok, tca_after} <- validate_datetime(params, "tca_after"),
         {:ok, tca_before} <- validate_datetime(params, "tca_before"),
         {:ok, page} <- validate_integer(params, "page", min: 1),
         {:ok, per_page} <- validate_integer(params, "per_page", min: 1, max: 100) do
      {:ok, %{
        asset_id: asset_id,
        severity: severity,
        status: status,
        tca_after: tca_after,
        tca_before: tca_before,
        page: page || 1,
        per_page: per_page || 20
      }}
    end
  end
  
  @doc """
  Sanitize user-provided string to prevent injection attacks.
  """
  def sanitize_string(nil), do: nil
  def sanitize_string(string) when is_binary(string) do
    string
    |> String.trim()
    |> HtmlEntities.decode()
    |> String.replace(~r/<[^>]*>/, "")  # Remove HTML tags
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")  # Remove control chars
  end
  def sanitize_string(other), do: to_string(other)
  
  # Private validation helpers
  
  defp validate_string(params, key, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    max_length = Keyword.get(opts, :max_length)
    min_length = Keyword.get(opts, :min_length, 0)
    
    case get_param(params, key) do
      nil when required ->
        {:error, [{key, "is required"}]}
        
      nil ->
        {:ok, nil}
        
      value when is_binary(value) ->
        sanitized = sanitize_string(value)
        
        cond do
          String.length(sanitized) < min_length ->
            {:error, [{key, "must be at least #{min_length} characters"}]}
            
          max_length && String.length(sanitized) > max_length ->
            {:error, [{key, "must be at most #{max_length} characters"}]}
            
          required && String.length(sanitized) == 0 ->
            {:error, [{key, "cannot be empty"}]}
            
          true ->
            {:ok, sanitized}
        end
        
      _ ->
        {:error, [{key, "must be a string"}]}
    end
  end
  
  defp validate_number(params, key, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    min = Keyword.get(opts, :min)
    max = Keyword.get(opts, :max)
    
    case get_param(params, key) do
      nil when required ->
        {:error, [{key, "is required"}]}
        
      nil ->
        {:ok, nil}
        
      value when is_number(value) ->
        validate_numeric_range(value, key, min, max)
        
      value when is_binary(value) ->
        case Float.parse(value) do
          {parsed, ""} -> validate_numeric_range(parsed, key, min, max)
          _ -> {:error, [{key, "must be a valid number"}]}
        end
        
      _ ->
        {:error, [{key, "must be a number"}]}
    end
  end
  
  defp validate_integer(params, key, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    min = Keyword.get(opts, :min)
    max = Keyword.get(opts, :max)
    
    case get_param(params, key) do
      nil when required ->
        {:error, [{key, "is required"}]}
        
      nil ->
        {:ok, nil}
        
      value when is_integer(value) ->
        validate_numeric_range(value, key, min, max)
        
      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> validate_numeric_range(parsed, key, min, max)
          _ -> {:error, [{key, "must be a valid integer"}]}
        end
        
      _ ->
        {:error, [{key, "must be an integer"}]}
    end
  end
  
  defp validate_numeric_range(value, key, min, max) do
    cond do
      min && value < min ->
        {:error, [{key, "must be at least #{min}"}]}
        
      max && value > max ->
        {:error, [{key, "must be at most #{max}"}]}
        
      true ->
        {:ok, value}
    end
  end
  
  defp validate_range(value, min, max, key) do
    cond do
      value < min -> {:error, [{key, "must be at least #{min}"}]}
      value > max -> {:error, [{key, "must be at most #{max}"}]}
      true -> {:ok, value}
    end
  end
  
  defp validate_enum(params, key, valid_values, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    
    case get_param(params, key) do
      nil when required ->
        {:error, [{key, "is required"}]}
        
      nil ->
        {:ok, nil}
        
      value when is_binary(value) ->
        try do
          atom_value = String.to_existing_atom(value)
          if atom_value in valid_values do
            {:ok, atom_value}
          else
            valid_str = Enum.map_join(valid_values, ", ", &to_string/1)
            {:error, [{key, "must be one of: #{valid_str}"}]}
          end
        rescue
          ArgumentError ->
            valid_str = Enum.map_join(valid_values, ", ", &to_string/1)
            {:error, [{key, "must be one of: #{valid_str}"}]}
        end
          
      value when is_atom(value) ->
        if value in valid_values do
          {:ok, value}
        else
          valid_str = Enum.map_join(valid_values, ", ", &to_string/1)
          {:error, [{key, "must be one of: #{valid_str}"}]}
        end
        
      _ ->
        {:error, [{key, "must be a string or atom"}]}
    end
  end
  
  defp validate_uuid(params, key, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    
    case get_param(params, key) do
      nil when required ->
        {:error, [{key, "is required"}]}
        
      nil ->
        {:ok, nil}
        
      value when is_binary(value) ->
        case Ecto.UUID.cast(value) do
          {:ok, uuid} -> {:ok, uuid}
          :error -> {:error, [{key, "must be a valid UUID"}]}
        end
        
      _ ->
        {:error, [{key, "must be a valid UUID string"}]}
    end
  end
  
  defp validate_datetime(params, key, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    
    case get_param(params, key) do
      nil when required ->
        {:error, [{key, "is required"}]}
        
      nil ->
        {:ok, nil}
        
      %DateTime{} = dt ->
        {:ok, dt}
        
      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _offset} -> {:ok, dt}
          {:error, _} -> {:error, [{key, "must be a valid ISO 8601 datetime"}]}
        end
        
      value when is_integer(value) ->
        case DateTime.from_unix(value) do
          {:ok, dt} -> {:ok, dt}
          {:error, _} -> {:error, [{key, "must be a valid Unix timestamp"}]}
        end
        
      _ ->
        {:error, [{key, "must be a valid datetime"}]}
    end
  end
  
  defp validate_json(params, key, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    
    case get_param(params, key) do
      nil when required ->
        {:error, [{key, "is required"}]}
        
      nil ->
        {:ok, nil}
        
      value when is_map(value) ->
        {:ok, value}
        
      value when is_binary(value) ->
        case Jason.decode(value) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, [{key, "must be valid JSON"}]}
        end
        
      _ ->
        {:error, [{key, "must be a valid JSON object"}]}
    end
  end
  
  defp validate_string_list(params, key, _opts \\ []) do
    case get_param(params, key) do
      nil ->
        {:ok, nil}
        
      list when is_list(list) ->
        if Enum.all?(list, &is_binary/1) do
          {:ok, Enum.map(list, &sanitize_string/1)}
        else
          {:error, [{key, "must be a list of strings"}]}
        end
        
      _ ->
        {:error, [{key, "must be a list"}]}
    end
  end
  
  defp validate_tle_optional(params) do
    line1 = get_param(params, "tle_line1")
    line2 = get_param(params, "tle_line2")
    
    cond do
      is_nil(line1) && is_nil(line2) ->
        {:ok, nil}
        
      is_nil(line1) || is_nil(line2) ->
        {:error, [{"tle", "both tle_line1 and tle_line2 must be provided together"}]}
        
      true ->
        validate_tle(params)
    end
  end
  
  defp parse_mode(mode) when is_binary(mode) do
    case String.downcase(mode) do
      "normal" -> :normal
      "safe" -> :safe
      "survival" -> :survival
      "standby" -> :standby
      _ -> nil
    end
  end
  
  defp get_param(params, key) when is_map(params) do
    Map.get(params, key) || Map.get(params, String.to_atom(key))
  end
  
  defp valid_tle_checksum?(line) do
    # TLE checksum is the modulo 10 sum of all digits, with '-' counting as 1
    {checksum_char, data} = String.split_at(line, -1)
    expected = String.to_integer(checksum_char)
    
    actual = 
      data
      |> String.graphemes()
      |> Enum.reduce(0, fn char, acc ->
        cond do
          char >= "0" && char <= "9" -> acc + String.to_integer(char)
          char == "-" -> acc + 1
          true -> acc
        end
      end)
      |> rem(10)
    
    actual == expected
  end
end
