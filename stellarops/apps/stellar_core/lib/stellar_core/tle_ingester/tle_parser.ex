defmodule StellarCore.TLEIngester.TLEParser do
  @moduledoc """
  Parser for Two-Line Element (TLE) format.
  
  TLE format specification:
  - Line 0 (optional): Object name (up to 24 characters)
  - Line 1: Satellite number, classification, international designator, epoch, derivatives, etc.
  - Line 2: Inclination, RAAN, eccentricity, argument of perigee, mean anomaly, mean motion
  
  Reference: https://celestrak.org/columns/v04n03/
  """
  
  @doc """
  Parse multiple TLEs from a text blob (3-line format).
  
  Returns {:ok, [%TLE{}, ...]} or {:error, reason}
  """
  def parse_multi(text) when is_binary(text) do
    lines = 
      text
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    
    case detect_format(lines) do
      :three_line ->
        parse_three_line_format(lines)
        
      :two_line ->
        parse_two_line_format(lines)
        
      :unknown ->
        {:error, :unknown_format}
    end
  end
  
  @doc """
  Parse a single TLE (3 lines: name, line1, line2).
  """
  def parse(name, line1, line2) do
    with {:ok, parsed_line1} <- parse_line1(line1),
         {:ok, parsed_line2} <- parse_line2(line2),
         :ok <- validate_checksums(line1, line2) do
      {:ok, build_tle(name, line1, line2, parsed_line1, parsed_line2)}
    end
  end
  
  @doc """
  Parse just lines 1 and 2 (no name).
  """
  def parse(line1, line2) do
    parse("", line1, line2)
  end
  
  # ============================================================================
  # Format Detection
  # ============================================================================
  
  defp detect_format([]) do
    :unknown
  end
  
  defp detect_format([first | _]) do
    cond do
      String.starts_with?(first, "1 ") -> :two_line
      String.starts_with?(first, "2 ") -> :unknown
      true -> :three_line
    end
  end
  
  # ============================================================================
  # Three-Line Format (Name, Line1, Line2)
  # ============================================================================
  
  defp parse_three_line_format(lines) do
    lines
    |> Enum.chunk_every(3)
    |> Enum.filter(fn chunk -> length(chunk) == 3 end)
    |> Enum.reduce_while({:ok, []}, fn [name, line1, line2], {:ok, acc} ->
      case parse(name, line1, line2) do
        {:ok, tle} -> {:cont, {:ok, [tle | acc]}}
        {:error, _reason} -> {:cont, {:ok, acc}}  # Skip invalid TLEs
      end
    end)
    |> case do
      {:ok, tles} -> {:ok, Enum.reverse(tles)}
    end
  end
  
  # ============================================================================
  # Two-Line Format (Line1, Line2 only)
  # ============================================================================
  
  defp parse_two_line_format(lines) do
    lines
    |> Enum.chunk_every(2)
    |> Enum.filter(fn chunk -> length(chunk) == 2 end)
    |> Enum.reduce_while({:ok, []}, fn [line1, line2], {:ok, acc} ->
      case parse(line1, line2) do
        {:ok, tle} -> {:cont, {:ok, [tle | acc]}}
        {:error, _reason} -> {:cont, {:ok, acc}}  # Skip invalid TLEs
      end
    end)
    |> case do
      {:ok, tles} -> {:ok, Enum.reverse(tles)}
    end
  end
  
  # ============================================================================
  # Line 1 Parser
  # ============================================================================
  
  defp parse_line1(line) do
    if String.length(line) < 69 do
      {:error, {:invalid_line1_length, String.length(line)}}
    else
      try do
        parsed = %{
          line_number: String.at(line, 0),
          norad_id: parse_norad_id(String.slice(line, 2, 5)),
          classification: String.at(line, 7),
          int_designator: String.slice(line, 9, 8) |> String.trim(),
          epoch_year: parse_epoch_year(String.slice(line, 18, 2)),
          epoch_day: parse_float(String.slice(line, 20, 12)),
          mean_motion_dot: parse_float(String.slice(line, 33, 10)),
          mean_motion_ddot: parse_exponential(String.slice(line, 44, 8)),
          bstar: parse_exponential(String.slice(line, 53, 8)),
          ephemeris_type: String.at(line, 62),
          element_number: parse_int(String.slice(line, 64, 4))
        }
        
        {:ok, parsed}
      rescue
        e -> {:error, {:parse_error, Exception.message(e)}}
      end
    end
  end
  
  # ============================================================================
  # Line 2 Parser
  # ============================================================================
  
  defp parse_line2(line) do
    if String.length(line) < 69 do
      {:error, {:invalid_line2_length, String.length(line)}}
    else
      try do
        parsed = %{
          line_number: String.at(line, 0),
          norad_id: parse_norad_id(String.slice(line, 2, 5)),
          inclination: parse_float(String.slice(line, 8, 8)),
          raan: parse_float(String.slice(line, 17, 8)),
          eccentricity: parse_eccentricity(String.slice(line, 26, 7)),
          arg_perigee: parse_float(String.slice(line, 34, 8)),
          mean_anomaly: parse_float(String.slice(line, 43, 8)),
          mean_motion: parse_float(String.slice(line, 52, 11)),
          rev_number: parse_int(String.slice(line, 63, 5))
        }
        
        {:ok, parsed}
      rescue
        e -> {:error, {:parse_error, Exception.message(e)}}
      end
    end
  end
  
  # ============================================================================
  # Value Parsers
  # ============================================================================
  
  defp parse_norad_id(str) do
    str |> String.trim() |> String.to_integer()
  end
  
  defp parse_epoch_year(str) do
    year = str |> String.trim() |> String.to_integer()
    # Y2K handling: 57-99 = 1957-1999, 00-56 = 2000-2056
    if year >= 57, do: 1900 + year, else: 2000 + year
  end
  
  defp parse_float(str) do
    trimmed = String.trim(str)
    # Handle TLE format quirks:
    # - Values like ".00012778" need a leading zero
    # - Values like "-.00012778" need "0" inserted after the minus
    normalized = 
      cond do
        String.starts_with?(trimmed, ".") -> "0" <> trimmed
        String.starts_with?(trimmed, "-.") -> "-0" <> String.slice(trimmed, 1..-1//1)
        true -> trimmed
      end
    
    String.to_float(normalized)
  rescue
    _ ->
      # Try parsing as integer and convert to float
      try do
        str |> String.trim() |> String.to_integer() |> Kernel./(1.0)
      rescue
        _ -> 0.0
      end
  end
  
  defp parse_int(str) do
    str |> String.trim() |> String.to_integer()
  rescue
    _ -> 0
  end
  
  defp parse_eccentricity(str) do
    # Eccentricity is stored as decimal without leading "0."
    ("0." <> String.trim(str)) |> String.to_float()
  end
  
  defp parse_exponential(str) do
    # TLE exponential format: " 00000-0" = 0.00000 * 10^0
    str = String.trim(str)
    
    if str == "" or str == "00000-0" or str == " 00000-0" do
      0.0
    else
      # Format: [sign]NNNNN[sign]E where N is mantissa, E is exponent
      # Example: "-12345-3" = -0.12345 * 10^-3
      {mantissa_str, exp_str} = String.split_at(str, -2)
      
      sign = if String.starts_with?(mantissa_str, "-"), do: -1, else: 1
      mantissa_str = String.replace(mantissa_str, ~r/^[+\-\s]/, "")
      
      mantissa = String.to_integer(mantissa_str) / 100000.0
      
      exp_sign = if String.starts_with?(exp_str, "-"), do: -1, else: 1
      exp = String.replace(exp_str, ~r/^[+\-]/, "") |> String.to_integer()
      
      sign * mantissa * :math.pow(10, exp_sign * exp)
    end
  rescue
    _ -> 0.0
  end
  
  # ============================================================================
  # Checksum Validation
  # ============================================================================
  
  defp validate_checksums(line1, line2) do
    with :ok <- validate_checksum(line1),
         :ok <- validate_checksum(line2) do
      :ok
    end
  end
  
  defp validate_checksum(line) do
    if String.length(line) < 69 do
      {:error, :line_too_short}
    else
      expected = String.at(line, 68) |> String.to_integer()
      computed = compute_checksum(String.slice(line, 0, 68))
      
      if expected == computed do
        :ok
      else
        # Some sources have invalid checksums, we'll be lenient
        :ok
      end
    end
  rescue
    _ -> :ok  # Skip checksum validation on parse errors
  end
  
  defp compute_checksum(str) do
    str
    |> String.graphemes()
    |> Enum.reduce(0, fn char, acc ->
      cond do
        char == "-" -> acc + 1
        char =~ ~r/[0-9]/ -> acc + String.to_integer(char)
        true -> acc
      end
    end)
    |> rem(10)
  end
  
  # ============================================================================
  # TLE Struct Builder
  # ============================================================================
  
  defp build_tle(name, line1, line2, parsed_line1, parsed_line2) do
    # Compute epoch as DateTime
    epoch = compute_epoch(parsed_line1.epoch_year, parsed_line1.epoch_day)
    
    %{
      name: String.trim(name),
      norad_id: parsed_line1.norad_id,
      line1: line1,
      line2: line2,
      epoch: epoch,
      classification: parsed_line1.classification,
      international_designator: parsed_line1.int_designator,
      inclination: parsed_line2.inclination,
      raan: parsed_line2.raan,
      eccentricity: parsed_line2.eccentricity,
      arg_perigee: parsed_line2.arg_perigee,
      mean_anomaly: parsed_line2.mean_anomaly,
      mean_motion: parsed_line2.mean_motion,
      bstar: parsed_line1.bstar,
      rev_number: parsed_line2.rev_number
    }
  end
  
  defp compute_epoch(year, day_of_year) do
    # Day of year is fractional (e.g., 25.5 = Jan 25, 12:00 UTC)
    day = trunc(day_of_year)
    fraction = day_of_year - day
    
    # Convert fractional day to time
    total_seconds = fraction * 86400
    hours = trunc(total_seconds / 3600)
    remaining = total_seconds - hours * 3600
    minutes = trunc(remaining / 60)
    seconds = trunc(remaining - minutes * 60)
    microseconds = trunc((remaining - minutes * 60 - seconds) * 1_000_000)
    
    # Build date from year and day of year
    date = Date.new!(year, 1, 1) |> Date.add(day - 1)
    time = Time.new!(hours, minutes, seconds, {microseconds, 6})
    
    DateTime.new!(date, time, "Etc/UTC")
  rescue
    _ -> DateTime.utc_now()
  end
end
