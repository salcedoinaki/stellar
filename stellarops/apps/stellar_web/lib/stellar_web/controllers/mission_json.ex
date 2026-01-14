defmodule StellarWeb.MissionJSON do
  @moduledoc """
  JSON rendering for missions.
  """

  alias StellarData.Missions.Mission

  def index(%{missions: missions}) do
    %{data: for(mission <- missions, do: data(mission))}
  end

  def show(%{mission: mission}) do
    %{data: data(mission)}
  end

  defp data(%Mission{} = mission) do
    %{
      id: mission.id,
      name: mission.name,
      description: mission.description,
      type: mission.type,
      priority: mission.priority,
      status: mission.status,
      satellite_id: mission.satellite_id,
      ground_station_id: mission.ground_station_id,
      # Scheduling
      deadline: mission.deadline,
      scheduled_at: mission.scheduled_at,
      started_at: mission.started_at,
      completed_at: mission.completed_at,
      # Retry info
      retry_count: mission.retry_count,
      max_retries: mission.max_retries,
      next_retry_at: mission.next_retry_at,
      last_error: mission.last_error,
      # Resources
      required_energy: mission.required_energy,
      required_memory: mission.required_memory,
      required_bandwidth: mission.required_bandwidth,
      estimated_duration: mission.estimated_duration,
      # Payload/Result
      payload: mission.payload,
      result: mission.result,
      # Timestamps
      inserted_at: mission.inserted_at,
      updated_at: mission.updated_at
    }
  end
end
