defmodule StellarWeb.PromEx.StellarPlugin do
  @moduledoc """
  Custom PromEx plugin for StellarOps domain metrics.
  
  Exposes:
  - stellar_satellites_active: Number of active satellites
  - stellar_satellites_by_mode: Satellites grouped by mode
  - stellar_satellite_energy_avg: Average energy level across constellation
  - stellar_tasks_pending: Number of pending tasks
  - stellar_tasks_completed_total: Total completed tasks
  - stellar_tasks_failed_total: Total failed tasks
  - stellar_commands_total: Total commands sent
  """

  use PromEx.Plugin

  alias StellarCore.Satellite

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    [
      satellite_metrics(poll_rate)
    ]
  end

  @impl true
  def event_metrics(_opts) do
    [
      task_event_metrics(),
      command_event_metrics()
    ]
  end

  defp satellite_metrics(poll_rate) do
    Polling.build(
      :stellar_satellite_metrics,
      poll_rate,
      {__MODULE__, :fetch_satellite_metrics, []},
      [
        last_value(
          [:stellar, :satellites, :active],
          event_name: [:stellar, :satellites, :count],
          description: "Number of active satellites in the constellation",
          measurement: :count,
          tags: []
        ),
        last_value(
          [:stellar, :satellites, :by_mode],
          event_name: [:stellar, :satellites, :by_mode],
          description: "Satellites grouped by operational mode",
          measurement: :count,
          tags: [:mode]
        ),
        last_value(
          [:stellar, :satellites, :energy_avg],
          event_name: [:stellar, :satellites, :energy],
          description: "Average energy level across all satellites (percentage)",
          measurement: :average,
          tags: [],
          unit: :percent
        ),
        last_value(
          [:stellar, :satellites, :memory_avg],
          event_name: [:stellar, :satellites, :memory],
          description: "Average memory usage across all satellites (percentage)",
          measurement: :average,
          tags: [],
          unit: :percent
        )
      ]
    )
  end

  defp task_event_metrics do
    Event.build(
      :stellar_task_events,
      [
        counter(
          [:stellar, :tasks, :completed, :total],
          event_name: [:stellar, :task, :completed],
          description: "Total number of completed satellite tasks",
          measurement: :count,
          tags: [:satellite_id, :task_type]
        ),
        counter(
          [:stellar, :tasks, :failed, :total],
          event_name: [:stellar, :task, :failed],
          description: "Total number of failed satellite tasks",
          measurement: :count,
          tags: [:satellite_id, :task_type, :reason]
        ),
        last_value(
          [:stellar, :tasks, :pending],
          event_name: [:stellar, :task, :queued],
          description: "Number of tasks currently pending",
          measurement: :queue_length,
          tags: []
        ),
        distribution(
          [:stellar, :tasks, :duration, :seconds],
          event_name: [:stellar, :task, :completed],
          description: "Task execution duration in seconds",
          measurement: :duration,
          tags: [:task_type],
          unit: {:native, :second},
          reporter_options: [
            buckets: [0.1, 0.5, 1, 5, 10, 30, 60, 120, 300]
          ]
        )
      ]
    )
  end

  defp command_event_metrics do
    Event.build(
      :stellar_command_events,
      [
        counter(
          [:stellar, :commands, :sent, :total],
          event_name: [:stellar, :command, :sent],
          description: "Total number of commands sent to satellites",
          measurement: :count,
          tags: [:satellite_id, :command_type]
        ),
        counter(
          [:stellar, :commands, :acknowledged, :total],
          event_name: [:stellar, :command, :acknowledged],
          description: "Total number of acknowledged commands",
          measurement: :count,
          tags: [:satellite_id, :command_type]
        ),
        distribution(
          [:stellar, :commands, :latency, :seconds],
          event_name: [:stellar, :command, :acknowledged],
          description: "Command round-trip latency",
          measurement: :latency,
          tags: [:command_type],
          unit: {:native, :second},
          reporter_options: [
            buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
          ]
        )
      ]
    )
  end

  @doc """
  Fetches satellite metrics from the constellation.
  Called by the polling mechanism.
  """
  def fetch_satellite_metrics do
    satellites = Satellite.Supervisor.list_satellites()
    
    states = 
      satellites
      |> Enum.map(fn {_id, pid} ->
        try do
          Satellite.Server.get_state(pid)
        rescue
          _ -> nil
        catch
          :exit, _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    count = length(states)
    
    # Emit satellite count
    :telemetry.execute(
      [:stellar, :satellites, :count],
      %{count: count},
      %{}
    )

    # Emit satellites by mode
    states
    |> Enum.group_by(& &1.mode)
    |> Enum.each(fn {mode, sats} ->
      :telemetry.execute(
        [:stellar, :satellites, :by_mode],
        %{count: length(sats)},
        %{mode: to_string(mode)}
      )
    end)

    # Emit average energy
    if count > 0 do
      avg_energy = 
        states
        |> Enum.map(& &1.energy)
        |> Enum.sum()
        |> Kernel./(count)
      
      :telemetry.execute(
        [:stellar, :satellites, :energy],
        %{average: avg_energy},
        %{}
      )

      # Emit average memory usage
      avg_memory =
        states
        |> Enum.map(& &1.memory_usage)
        |> Enum.sum()
        |> Kernel./(count)

      :telemetry.execute(
        [:stellar, :satellites, :memory],
        %{average: avg_memory},
        %{}
      )
    end
  end
end
