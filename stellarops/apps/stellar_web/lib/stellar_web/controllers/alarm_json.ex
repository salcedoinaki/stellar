defmodule StellarWeb.AlarmJSON do
  @moduledoc """
  JSON rendering for alarms.
  """

  def index(%{alarms: alarms}) do
    %{data: for(alarm <- alarms, do: data(alarm))}
  end

  def show(%{alarm: alarm}) do
    %{data: data(alarm)}
  end

  def summary(%{summary: summary}) do
    %{data: summary}
  end

  defp data(alarm) do
    %{
      id: alarm.id,
      type: alarm.type,
      severity: alarm.severity,
      message: alarm.message,
      source: alarm.source,
      details: alarm.details,
      status: alarm.status,
      created_at: alarm.created_at,
      acknowledged_at: alarm.acknowledged_at,
      acknowledged_by: alarm.acknowledged_by,
      resolved_at: alarm.resolved_at
    }
  end
end
