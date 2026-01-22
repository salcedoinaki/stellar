defmodule StellarCore.Logger.JSONFormatter do
  @moduledoc """
  JSON formatter for structured logging in production environments.
  
  Formats log entries as JSON objects for consumption by log aggregation
  systems like Elasticsearch, Loki, or CloudWatch.
  
  ## Configuration
  
  In `config/prod.exs`:
  
      config :logger, :console,
        format: {StellarCore.Logger.JSONFormatter, :format},
        metadata: :all
  
  ## Output Format
  
      {
        "timestamp": "2024-01-15T10:30:00.000Z",
        "level": "info",
        "message": "Satellite state changed",
        "domain": "satellite",
        "satellite_id": "sat-123",
        "request_id": "abc-xyz"
      }
  """

  @doc """
  Formats a log entry as JSON.
  """
  def format(level, message, timestamp, metadata) do
    json =
      %{
        timestamp: format_timestamp(timestamp),
        level: to_string(level),
        message: IO.iodata_to_binary(message)
      }
      |> merge_metadata(metadata)
      |> Jason.encode!()

    [json, "\n"]
  rescue
    e ->
      # Fallback to basic format if JSON encoding fails
      ["Failed to format log: ", inspect({level, message, metadata}), 
       " Error: ", inspect(e), "\n"]
  end

  defp format_timestamp({date, {hours, minutes, seconds, microseconds}}) do
    {{year, month, day}, {hours, minutes, seconds}} = {date, {hours, minutes, seconds}}

    NaiveDateTime.new!(year, month, day, hours, minutes, seconds, microseconds * 1000)
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp merge_metadata(json, metadata) do
    metadata
    |> Enum.reduce(json, fn {key, value}, acc ->
      Map.put(acc, key, format_value(value))
    end)
  end

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_atom(value), do: to_string(value)
  defp format_value(value) when is_number(value), do: value
  defp format_value(value) when is_list(value), do: Enum.map(value, &format_value/1)
  defp format_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_value(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp format_value(%Date{} = d), do: Date.to_iso8601(d)
  defp format_value(%_{} = struct), do: inspect(struct)
  defp format_value(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {to_string(k), format_value(v)} end)
  end
  defp format_value(value) when is_tuple(value), do: inspect(value)
  defp format_value(value) when is_pid(value), do: inspect(value)
  defp format_value(value) when is_reference(value), do: inspect(value)
  defp format_value(value) when is_function(value), do: inspect(value)
  defp format_value(value), do: inspect(value)
end
