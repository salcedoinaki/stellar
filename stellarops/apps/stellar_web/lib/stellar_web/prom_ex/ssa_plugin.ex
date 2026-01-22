defmodule StellarWeb.PromEx.SSAPlugin do
  @moduledoc """
  PromEx plugin for Space Situational Awareness (SSA) metrics.
  
  Exposes:
  - stellar_conjunctions_active: Active conjunction events by severity
  - stellar_conjunctions_detected_total: Total conjunction detections
  - stellar_coas_pending: Pending Course of Action recommendations
  - stellar_coas_by_status: COAs grouped by status (pending/approved/rejected)
  - stellar_coas_generated_total: Total COAs generated
  - stellar_space_objects_total: Tracked space objects by type
  - stellar_detection_cycle_duration_seconds: Conjunction detection cycle time
  - stellar_tle_age_seconds: Average TLE data age
  - stellar_threats_active: Active threat assessments by severity
  """

  use PromEx.Plugin

  alias StellarData.SSA

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 10_000)

    [
      conjunction_polling_metrics(poll_rate),
      coa_polling_metrics(poll_rate),
      space_object_polling_metrics(poll_rate),
      tle_polling_metrics(poll_rate)
    ]
  end

  @impl true
  def event_metrics(_opts) do
    [
      conjunction_event_metrics(),
      coa_event_metrics(),
      screening_event_metrics()
    ]
  end

  # ============================================================================
  # Polling Metrics
  # ============================================================================

  defp conjunction_polling_metrics(poll_rate) do
    Polling.build(
      :stellar_ssa_conjunction_metrics,
      poll_rate,
      {__MODULE__, :fetch_conjunction_metrics, []},
      [
        last_value(
          [:stellar, :conjunctions, :active],
          event_name: [:stellar, :ssa, :conjunctions, :active],
          description: "Number of active conjunction events by severity",
          measurement: :count,
          tags: [:severity]
        ),
        last_value(
          [:stellar, :conjunctions, :by_status],
          event_name: [:stellar, :ssa, :conjunctions, :by_status],
          description: "Conjunction events by status",
          measurement: :count,
          tags: [:status]
        ),
        last_value(
          [:stellar, :threats, :active],
          event_name: [:stellar, :ssa, :threats, :active],
          description: "Active threat assessments by severity",
          measurement: :count,
          tags: [:severity]
        )
      ]
    )
  end

  defp coa_polling_metrics(poll_rate) do
    Polling.build(
      :stellar_ssa_coa_metrics,
      poll_rate,
      {__MODULE__, :fetch_coa_metrics, []},
      [
        last_value(
          [:stellar, :coas, :pending],
          event_name: [:stellar, :ssa, :coas, :pending],
          description: "Number of COAs pending review",
          measurement: :count,
          tags: []
        ),
        last_value(
          [:stellar, :coas, :by_status],
          event_name: [:stellar, :ssa, :coas, :by_status],
          description: "COAs grouped by status",
          measurement: :count,
          tags: [:status]
        ),
        last_value(
          [:stellar, :coas, :by_type],
          event_name: [:stellar, :ssa, :coas, :by_type],
          description: "COAs grouped by maneuver type",
          measurement: :count,
          tags: [:maneuver_type]
        )
      ]
    )
  end

  defp space_object_polling_metrics(poll_rate) do
    Polling.build(
      :stellar_ssa_object_metrics,
      poll_rate,
      {__MODULE__, :fetch_space_object_metrics, []},
      [
        last_value(
          [:stellar, :space_objects, :total],
          event_name: [:stellar, :ssa, :objects, :total],
          description: "Total tracked space objects by type",
          measurement: :count,
          tags: [:type]
        ),
        last_value(
          [:stellar, :space_objects, :by_regime],
          event_name: [:stellar, :ssa, :objects, :by_regime],
          description: "Space objects by orbital regime",
          measurement: :count,
          tags: [:regime]
        )
      ]
    )
  end

  defp tle_polling_metrics(poll_rate) do
    Polling.build(
      :stellar_ssa_tle_metrics,
      poll_rate,
      {__MODULE__, :fetch_tle_metrics, []},
      [
        last_value(
          [:stellar, :tle, :age, :seconds],
          event_name: [:stellar, :ssa, :tle, :age],
          description: "Average TLE data age in seconds",
          measurement: :average_age,
          tags: [],
          unit: :second
        ),
        last_value(
          [:stellar, :tle, :stale, :count],
          event_name: [:stellar, :ssa, :tle, :stale],
          description: "Number of TLEs older than 7 days",
          measurement: :count,
          tags: []
        )
      ]
    )
  end

  # ============================================================================
  # Event Metrics
  # ============================================================================

  defp conjunction_event_metrics do
    Event.build(
      :stellar_ssa_conjunction_events,
      [
        counter(
          [:stellar, :conjunctions, :detected, :total],
          event_name: [:stellar, :ssa, :conjunction, :detected],
          description: "Total number of conjunction events detected",
          measurement: :count,
          tags: [:severity, :primary_type]
        ),
        counter(
          [:stellar, :conjunctions, :resolved, :total],
          event_name: [:stellar, :ssa, :conjunction, :resolved],
          description: "Total number of conjunction events resolved",
          measurement: :count,
          tags: [:resolution]
        ),
        distribution(
          [:stellar, :detection, :cycle, :duration, :seconds],
          event_name: [:stellar, :ssa, :detection, :cycle, :complete],
          description: "Conjunction detection cycle duration",
          measurement: :duration,
          tags: [],
          unit: {:native, :second},
          reporter_options: [
            buckets: [1, 5, 10, 30, 60, 120, 300, 600]
          ]
        ),
        distribution(
          [:stellar, :conjunction, :miss_distance, :km],
          event_name: [:stellar, :ssa, :conjunction, :detected],
          description: "Distribution of miss distances in kilometers",
          measurement: :miss_distance,
          tags: [:severity],
          reporter_options: [
            buckets: [0.1, 0.5, 1, 5, 10, 50, 100, 500, 1000]
          ]
        )
      ]
    )
  end

  defp coa_event_metrics do
    Event.build(
      :stellar_ssa_coa_events,
      [
        counter(
          [:stellar, :coas, :generated, :total],
          event_name: [:stellar, :ssa, :coa, :generated],
          description: "Total number of COAs generated",
          measurement: :count,
          tags: [:maneuver_type, :conjunction_severity]
        ),
        counter(
          [:stellar, :coas, :approved, :total],
          event_name: [:stellar, :ssa, :coa, :approved],
          description: "Total number of COAs approved",
          measurement: :count,
          tags: [:maneuver_type]
        ),
        counter(
          [:stellar, :coas, :rejected, :total],
          event_name: [:stellar, :ssa, :coa, :rejected],
          description: "Total number of COAs rejected",
          measurement: :count,
          tags: [:reason]
        ),
        counter(
          [:stellar, :coas, :executed, :total],
          event_name: [:stellar, :ssa, :coa, :executed],
          description: "Total number of COAs successfully executed",
          measurement: :count,
          tags: [:maneuver_type]
        ),
        distribution(
          [:stellar, :coas, :decision, :time, :seconds],
          event_name: [:stellar, :ssa, :coa, :decision_made],
          description: "Time from COA generation to decision",
          measurement: :decision_time,
          tags: [:decision],
          unit: {:native, :second},
          reporter_options: [
            buckets: [60, 300, 600, 1800, 3600, 7200, 14400, 28800]
          ]
        ),
        distribution(
          [:stellar, :coas, :delta_v, :m_s],
          event_name: [:stellar, :ssa, :coa, :generated],
          description: "Distribution of delta-v requirements for COAs",
          measurement: :delta_v,
          tags: [:maneuver_type],
          reporter_options: [
            buckets: [0.01, 0.05, 0.1, 0.5, 1, 5, 10, 50]
          ]
        )
      ]
    )
  end

  defp screening_event_metrics do
    Event.build(
      :stellar_ssa_screening_events,
      [
        counter(
          [:stellar, :screening, :runs, :total],
          event_name: [:stellar, :ssa, :screening, :complete],
          description: "Total number of screening runs completed",
          measurement: :count,
          tags: [:trigger]
        ),
        distribution(
          [:stellar, :screening, :duration, :seconds],
          event_name: [:stellar, :ssa, :screening, :complete],
          description: "Screening run duration",
          measurement: :duration,
          tags: [],
          unit: {:native, :second},
          reporter_options: [
            buckets: [1, 5, 10, 30, 60, 120, 300]
          ]
        ),
        last_value(
          [:stellar, :screening, :objects, :processed],
          event_name: [:stellar, :ssa, :screening, :complete],
          description: "Number of objects processed in last screening run",
          measurement: :objects_processed,
          tags: []
        )
      ]
    )
  end

  # ============================================================================
  # Metric Fetch Functions
  # ============================================================================

  @doc """
  Fetches conjunction and threat metrics from the SSA context.
  """
  def fetch_conjunction_metrics do
    try do
      # Fetch active conjunctions by severity
      for severity <- [:critical, :high, :medium, :low] do
        count = SSA.count_conjunctions_by_severity(severity)
        :telemetry.execute(
          [:stellar, :ssa, :conjunctions, :active],
          %{count: count},
          %{severity: to_string(severity)}
        )
      end

      # Fetch conjunctions by status
      for status <- [:detected, :monitoring, :mitigating, :resolved] do
        count = SSA.count_conjunctions_by_status(status)
        :telemetry.execute(
          [:stellar, :ssa, :conjunctions, :by_status],
          %{count: count},
          %{status: to_string(status)}
        )
      end

      # Fetch active threats by severity
      for severity <- [:critical, :high, :medium, :low] do
        count = SSA.count_threats_by_severity(severity)
        :telemetry.execute(
          [:stellar, :ssa, :threats, :active],
          %{count: count},
          %{severity: to_string(severity)}
        )
      end
    rescue
      _ -> :ok
    end
  end

  @doc """
  Fetches COA metrics from the SSA context.
  """
  def fetch_coa_metrics do
    try do
      # Pending COAs
      pending_count = SSA.count_coas_by_status(:pending)
      :telemetry.execute(
        [:stellar, :ssa, :coas, :pending],
        %{count: pending_count},
        %{}
      )

      # COAs by status
      for status <- [:pending, :approved, :rejected, :executed, :expired] do
        count = SSA.count_coas_by_status(status)
        :telemetry.execute(
          [:stellar, :ssa, :coas, :by_status],
          %{count: count},
          %{status: to_string(status)}
        )
      end

      # COAs by maneuver type
      for type <- [:raise_orbit, :lower_orbit, :phase_shift, :inclination_change, :hold_position] do
        count = SSA.count_coas_by_type(type)
        :telemetry.execute(
          [:stellar, :ssa, :coas, :by_type],
          %{count: count},
          %{maneuver_type: to_string(type)}
        )
      end
    rescue
      _ -> :ok
    end
  end

  @doc """
  Fetches space object metrics from the SSA context.
  """
  def fetch_space_object_metrics do
    try do
      # Objects by type
      for type <- [:satellite, :debris, :rocket_body, :unknown] do
        count = SSA.count_space_objects_by_type(type)
        :telemetry.execute(
          [:stellar, :ssa, :objects, :total],
          %{count: count},
          %{type: to_string(type)}
        )
      end

      # Objects by orbital regime
      for regime <- [:leo, :meo, :geo, :heo, :sso] do
        count = SSA.count_space_objects_by_regime(regime)
        :telemetry.execute(
          [:stellar, :ssa, :objects, :by_regime],
          %{count: count},
          %{regime: to_string(regime)}
        )
      end
    rescue
      _ -> :ok
    end
  end

  @doc """
  Fetches TLE freshness metrics.
  """
  def fetch_tle_metrics do
    try do
      # Average TLE age
      avg_age = SSA.get_average_tle_age_seconds()
      :telemetry.execute(
        [:stellar, :ssa, :tle, :age],
        %{average_age: avg_age || 0},
        %{}
      )

      # Count of stale TLEs (older than 7 days)
      stale_count = SSA.count_stale_tles(days: 7)
      :telemetry.execute(
        [:stellar, :ssa, :tle, :stale],
        %{count: stale_count || 0},
        %{}
      )
    rescue
      _ -> :ok
    end
  end
end
