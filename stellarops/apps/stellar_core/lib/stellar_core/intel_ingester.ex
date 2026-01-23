defmodule StellarCore.IntelIngester do
  @moduledoc """
  Ingests threat intelligence data from external sources and manual classification.
  
  Creates and updates ThreatAssessment records for space objects based on:
  - External intelligence feeds
  - Manual operator classification
  - Behavioral analysis
  
  Provides audit trail for all classification changes.
  """
  
  use GenServer
  require Logger
  
  alias StellarData.SSA
  alias StellarData.SSA.ThreatAssessment
  
  @default_refresh_interval :timer.hours(12)
  
  # ============================================================================
  # Client API
  # ============================================================================
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Ingest threat intelligence from configured sources.
  """
  def ingest_all do
    GenServer.call(__MODULE__, :ingest_all, :timer.minutes(5))
  end
  
  @doc """
  Manually classify a space object as a threat.
  
  ## Parameters
  - space_object_id: The space object to classify
  - classification: :hostile, :suspicious, :unknown, or :friendly
  - params: Additional classification parameters
    - :capabilities - List of capabilities (e.g., ["ASAT", "RPOD", "MANEUVER"])
    - :threat_level - :critical, :high, :medium, :low, or :none
    - :intel_summary - Summary of intelligence
    - :notes - Additional notes
    - :confidence_level - :high, :medium, or :low
  - assessed_by: User/operator ID who made the classification
  """
  def classify(space_object_id, classification, params \\ %{}, assessed_by \\ nil) do
    GenServer.call(__MODULE__, {:classify, space_object_id, classification, params, assessed_by})
  end
  
  @doc """
  Get the threat assessment for a space object.
  """
  def get_assessment(space_object_id) do
    GenServer.call(__MODULE__, {:get_assessment, space_object_id})
  end
  
  @doc """
  Get classification history for a space object.
  """
  def get_classification_history(space_object_id) do
    GenServer.call(__MODULE__, {:get_history, space_object_id})
  end
  
  @doc """
  Get all objects with a specific threat level.
  """
  def get_by_threat_level(level) when level in [:critical, :high, :medium, :low, :none] do
    GenServer.call(__MODULE__, {:get_by_level, level})
  end
  
  @doc """
  Get all hostile objects.
  """
  def get_hostile_objects do
    GenServer.call(__MODULE__, :get_hostile)
  end
  
  # ============================================================================
  # GenServer Callbacks
  # ============================================================================
  
  @impl true
  def init(opts) do
    refresh_interval = Keyword.get(opts, :refresh_interval, @default_refresh_interval)
    auto_start = Keyword.get(opts, :auto_start, false)
    
    state = %{
      refresh_interval: refresh_interval,
      last_ingestion: nil,
      intel_sources: configure_sources(),
      enabled: auto_start
    }
    
    if auto_start do
      Process.send_after(self(), :scheduled_ingest, :timer.minutes(5))
    end
    
    Logger.info("IntelIngester started")
    {:ok, state}
  end
  
  @impl true
  def handle_call(:ingest_all, _from, state) do
    result = do_ingest_all(state.intel_sources)
    new_state = %{state | last_ingestion: DateTime.utc_now()}
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:classify, object_id, classification, params, assessed_by}, _from, state) do
    result = do_classify(object_id, classification, params, assessed_by)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:get_assessment, object_id}, _from, state) do
    result = SSA.get_threat_assessment(object_id)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:get_history, object_id}, _from, state) do
    result = SSA.get_threat_assessment_history(object_id)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:get_by_level, level}, _from, state) do
    result = SSA.list_threat_assessments_by_level(level)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call(:get_hostile, _from, state) do
    result = SSA.list_threat_assessments_by_classification(:hostile)
    {:reply, result, state}
  end
  
  @impl true
  def handle_info(:scheduled_ingest, state) do
    if state.enabled do
      Logger.info("Starting scheduled intel ingestion")
      do_ingest_all(state.intel_sources)
      Process.send_after(self(), :scheduled_ingest, state.refresh_interval)
    end
    {:noreply, state}
  end
  
  # ============================================================================
  # Private Functions
  # ============================================================================
  
  defp configure_sources do
    # Configure available intel sources from environment/config
    sources = []
    
    # Add custom API sources if configured
    if api_url = System.get_env("INTEL_API_URL") do
      sources ++ [{:custom_api, api_url}]
    else
      sources
    end
  end
  
  defp do_ingest_all(sources) do
    Logger.info("Ingesting intelligence from #{length(sources)} sources")
    
    results = 
      sources
      |> Enum.map(fn source ->
        case ingest_from_source(source) do
          {:ok, count} -> {:ok, source, count}
          {:error, reason} -> {:error, source, reason}
        end
      end)
    
    successes = Enum.count(results, fn r -> match?({:ok, _, _}, r) end)
    total = Enum.filter(results, fn r -> match?({:ok, _, _}, r) end)
            |> Enum.map(fn {:ok, _, count} -> count end)
            |> Enum.sum()
    
    Logger.info("Intel ingestion complete: #{total} assessments from #{successes} sources")
    
    {:ok, %{total: total, sources: successes}}
  end
  
  defp ingest_from_source({:custom_api, url}) do
    Logger.debug("Fetching intel from: #{url}")
    
    case fetch_intel_api(url) do
      {:ok, data} ->
        count = process_intel_data(data)
        {:ok, count}
        
      {:error, reason} ->
        Logger.error("Failed to fetch intel from #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp ingest_from_source(unknown) do
    Logger.warning("Unknown intel source type: #{inspect(unknown)}")
    {:error, :unknown_source}
  end
  
  defp fetch_intel_api(url) do
    headers = [
      {"Accept", "application/json"},
      {"User-Agent", "StellarOps/1.0"}
    ]
    
    # Add API key if configured
    headers = 
      if api_key = System.get_env("INTEL_API_KEY") do
        [{"Authorization", "Bearer #{api_key}"} | headers]
      else
        headers
      end
    
    case :httpc.request(:get, {String.to_charlist(url), headers},
           [{:timeout, 30_000}], [{:body_format, :binary}]) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, Jason.decode!(body)}
        
      {:ok, {{_, status, _}, _headers, body}} ->
        {:error, {:http_error, status, body}}
        
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, {:decode_error, Exception.message(e)}}
  end
  
  defp process_intel_data(data) when is_list(data) do
    data
    |> Enum.map(&process_intel_record/1)
    |> Enum.count(&match?({:ok, _}, &1))
  end
  
  defp process_intel_data(_), do: 0
  
  defp process_intel_record(%{
    "norad_id" => norad_id,
    "classification" => classification,
    "threat_level" => threat_level
  } = record) do
    # Find or create the space object
    case SSA.get_space_object_by_norad_id(norad_id) do
      nil ->
        {:error, :object_not_found}
        
      object ->
        params = %{
          classification: normalize_classification(classification),
          threat_level: normalize_threat_level(threat_level),
          capabilities: Map.get(record, "capabilities", []),
          intel_summary: Map.get(record, "intel_summary"),
          confidence_level: normalize_confidence(Map.get(record, "confidence", "medium")),
          assessed_by: "intel_feed"
        }
        
        do_classify(object.id, params.classification, params, "intel_feed")
    end
  end
  
  defp process_intel_record(_), do: {:error, :invalid_record}
  
  defp do_classify(object_id, classification, params, assessed_by) do
    # Get existing assessment if any
    existing = SSA.get_threat_assessment(object_id)
    
    attrs = %{
      space_object_id: object_id,
      classification: classification,
      threat_level: Map.get(params, :threat_level, infer_threat_level(classification)),
      capabilities: Map.get(params, :capabilities, []),
      intel_summary: Map.get(params, :intel_summary),
      notes: Map.get(params, :notes),
      confidence_level: Map.get(params, :confidence_level, :medium),
      assessed_by: assessed_by,
      assessed_at: DateTime.utc_now()
    }
    
    result = if existing do
      # Create audit trail entry before updating
      log_classification_change(existing, attrs)
      SSA.update_threat_assessment(existing, attrs)
    else
      SSA.create_threat_assessment(attrs)
    end
    
    case result do
      {:ok, assessment} ->
        # Emit telemetry
        :telemetry.execute(
          [:stellar, :intel, :classification],
          %{},
          %{
            object_id: object_id,
            classification: classification,
            threat_level: attrs.threat_level,
            assessed_by: assessed_by
          }
        )
        
        # Raise alarm for hostile classifications
        if classification == :hostile do
          StellarCore.Alarms.raise_alarm(
            :hostile_object_detected,
            "Space object #{object_id} classified as hostile",
            :major,
            "intel_ingester",
            %{object_id: object_id, threat_level: attrs.threat_level}
          )
        end
        
        Logger.info("Classified object #{object_id} as #{classification} (threat_level: #{attrs.threat_level})")
        {:ok, assessment}
        
      {:error, reason} = error ->
        Logger.error("Failed to classify object #{object_id}: #{inspect(reason)}")
        error
    end
  end
  
  defp infer_threat_level(:hostile), do: :high
  defp infer_threat_level(:suspicious), do: :medium
  defp infer_threat_level(:unknown), do: :low
  defp infer_threat_level(:friendly), do: :none
  defp infer_threat_level(_), do: :unknown
  
  defp normalize_classification(str) when is_binary(str) do
    case String.downcase(str) do
      "hostile" -> :hostile
      "suspicious" -> :suspicious
      "friendly" -> :friendly
      _ -> :unknown
    end
  end
  defp normalize_classification(atom) when is_atom(atom), do: atom
  
  defp normalize_threat_level(str) when is_binary(str) do
    case String.downcase(str) do
      "critical" -> :critical
      "high" -> :high
      "medium" -> :medium
      "low" -> :low
      "none" -> :none
      _ -> :low
    end
  end
  defp normalize_threat_level(atom) when is_atom(atom), do: atom
  
  defp normalize_confidence(str) when is_binary(str) do
    case String.downcase(str) do
      "high" -> :high
      "medium" -> :medium
      "low" -> :low
      _ -> :medium
    end
  end
  defp normalize_confidence(atom) when is_atom(atom), do: atom
  
  defp log_classification_change(old, new) do
    change = %{
      object_id: old.space_object_id,
      old_classification: old.classification,
      new_classification: new.classification,
      old_threat_level: old.threat_level,
      new_threat_level: new.threat_level,
      changed_by: new.assessed_by,
      changed_at: DateTime.utc_now()
    }
    
    Logger.info("Classification change: #{inspect(change)}")
    
    # Store in audit trail
    SSA.create_classification_audit(change)
  end
end
