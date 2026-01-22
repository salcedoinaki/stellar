defmodule StellarCore.SSA.Telemetry do
  @moduledoc """
  Telemetry helper module for Space Situational Awareness events.
  
  Provides convenient functions for emitting telemetry events that are
  captured by the PromEx SSA plugin for Prometheus metrics.
  
  ## Event Categories
  
  - Conjunction events: Detection, resolution, status changes
  - COA events: Generation, approval, rejection, execution
  - Screening events: Run completion, timing
  - TLE events: Fetch, parse, refresh
  """

  @doc """
  Emits a conjunction detected event.
  
  ## Parameters
  - severity: :critical | :high | :medium | :low
  - primary_type: Type of primary object (:satellite | :debris | :rocket_body)
  - miss_distance: Predicted miss distance in kilometers
  - metadata: Additional metadata map
  """
  def emit_conjunction_detected(severity, primary_type, miss_distance, metadata \\ %{}) do
    :telemetry.execute(
      [:stellar, :ssa, :conjunction, :detected],
      %{count: 1, miss_distance: miss_distance},
      Map.merge(%{severity: to_string(severity), primary_type: to_string(primary_type)}, metadata)
    )
  end

  @doc """
  Emits a conjunction resolved event.
  
  ## Parameters
  - resolution: :passed | :maneuver_executed | :natural_decay | :monitoring
  - metadata: Additional metadata map
  """
  def emit_conjunction_resolved(resolution, metadata \\ %{}) do
    :telemetry.execute(
      [:stellar, :ssa, :conjunction, :resolved],
      %{count: 1},
      Map.merge(%{resolution: to_string(resolution)}, metadata)
    )
  end

  @doc """
  Emits a COA generated event.
  
  ## Parameters
  - maneuver_type: :raise_orbit | :lower_orbit | :phase_shift | etc.
  - conjunction_severity: Severity of the associated conjunction
  - delta_v: Required delta-v in m/s
  - metadata: Additional metadata map
  """
  def emit_coa_generated(maneuver_type, conjunction_severity, delta_v, metadata \\ %{}) do
    :telemetry.execute(
      [:stellar, :ssa, :coa, :generated],
      %{count: 1, delta_v: delta_v},
      Map.merge(%{
        maneuver_type: to_string(maneuver_type),
        conjunction_severity: to_string(conjunction_severity)
      }, metadata)
    )
  end

  @doc """
  Emits a COA approved event.
  
  ## Parameters
  - maneuver_type: Type of maneuver approved
  - metadata: Additional metadata map
  """
  def emit_coa_approved(maneuver_type, metadata \\ %{}) do
    :telemetry.execute(
      [:stellar, :ssa, :coa, :approved],
      %{count: 1},
      Map.merge(%{maneuver_type: to_string(maneuver_type)}, metadata)
    )
  end

  @doc """
  Emits a COA rejected event.
  
  ## Parameters
  - reason: Reason for rejection
  - metadata: Additional metadata map
  """
  def emit_coa_rejected(reason, metadata \\ %{}) do
    :telemetry.execute(
      [:stellar, :ssa, :coa, :rejected],
      %{count: 1},
      Map.merge(%{reason: to_string(reason)}, metadata)
    )
  end

  @doc """
  Emits a COA executed event.
  
  ## Parameters
  - maneuver_type: Type of maneuver executed
  - metadata: Additional metadata map
  """
  def emit_coa_executed(maneuver_type, metadata \\ %{}) do
    :telemetry.execute(
      [:stellar, :ssa, :coa, :executed],
      %{count: 1},
      Map.merge(%{maneuver_type: to_string(maneuver_type)}, metadata)
    )
  end

  @doc """
  Emits a COA decision made event with timing.
  
  ## Parameters
  - decision: :approved | :rejected
  - decision_time_seconds: Time from generation to decision
  - metadata: Additional metadata map
  """
  def emit_coa_decision_made(decision, decision_time_seconds, metadata \\ %{}) do
    :telemetry.execute(
      [:stellar, :ssa, :coa, :decision_made],
      %{decision_time: decision_time_seconds},
      Map.merge(%{decision: to_string(decision)}, metadata)
    )
  end

  @doc """
  Emits a screening run completed event.
  
  ## Parameters
  - trigger: :scheduled | :manual | :tle_update | :new_object
  - duration_seconds: Time taken for the screening run
  - objects_processed: Number of objects screened
  - metadata: Additional metadata map
  """
  def emit_screening_complete(trigger, duration_seconds, objects_processed, metadata \\ %{}) do
    :telemetry.execute(
      [:stellar, :ssa, :screening, :complete],
      %{count: 1, duration: duration_seconds, objects_processed: objects_processed},
      Map.merge(%{trigger: to_string(trigger)}, metadata)
    )
  end

  @doc """
  Emits a detection cycle completed event.
  
  ## Parameters
  - duration_seconds: Time taken for the detection cycle
  - metadata: Additional metadata map
  """
  def emit_detection_cycle_complete(duration_seconds, metadata \\ %{}) do
    :telemetry.execute(
      [:stellar, :ssa, :detection, :cycle, :complete],
      %{duration: duration_seconds},
      metadata
    )
  end

  @doc """
  Emits a TLE fetch event.
  
  ## Parameters
  - source: :celestrak | :space_track
  - count: Number of TLEs fetched
  - duration_seconds: Time taken for the fetch
  - metadata: Additional metadata map
  """
  def emit_tle_fetched(source, count, duration_seconds, metadata \\ %{}) do
    :telemetry.execute(
      [:stellar, :ssa, :tle, :fetched],
      %{count: count, duration: duration_seconds},
      Map.merge(%{source: to_string(source)}, metadata)
    )
  end

  @doc """
  Emits a TLE parse error event.
  
  ## Parameters
  - source: Source of the TLE data
  - error_type: Type of parse error
  - metadata: Additional metadata map
  """
  def emit_tle_parse_error(source, error_type, metadata \\ %{}) do
    :telemetry.execute(
      [:stellar, :ssa, :tle, :parse_error],
      %{count: 1},
      Map.merge(%{source: to_string(source), error_type: to_string(error_type)}, metadata)
    )
  end

  @doc """
  Times and emits a detection cycle.
  
  Returns the result of the provided function.
  """
  def time_detection_cycle(fun, metadata \\ %{}) when is_function(fun, 0) do
    start_time = System.monotonic_time(:millisecond)
    result = fun.()
    duration_seconds = (System.monotonic_time(:millisecond) - start_time) / 1000

    emit_detection_cycle_complete(duration_seconds, metadata)

    result
  end

  @doc """
  Times and emits a screening run.
  
  Returns the result of the provided function.
  """
  def time_screening(trigger, fun, metadata \\ %{}) when is_function(fun, 0) do
    start_time = System.monotonic_time(:millisecond)
    result = fun.()
    duration_seconds = (System.monotonic_time(:millisecond) - start_time) / 1000

    objects_processed =
      case result do
        {:ok, count} when is_integer(count) -> count
        list when is_list(list) -> length(list)
        _ -> 0
      end

    emit_screening_complete(trigger, duration_seconds, objects_processed, metadata)

    result
  end
end
