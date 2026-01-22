defmodule StellarCore.Observability.Tracer do
  @moduledoc """
  OpenTelemetry tracing configuration and utilities.
  
  Provides distributed tracing capabilities for StellarOps using OpenTelemetry.
  Traces can be exported to Jaeger, Zipkin, or any OTLP-compatible backend.
  
  ## Configuration
  
  In `config/runtime.exs`:
  
      config :opentelemetry,
        span_processor: :batch,
        traces_exporter: :otlp
  
      config :opentelemetry_exporter,
        otlp_protocol: :http_protobuf,
        otlp_endpoint: System.get_env("OTLP_ENDPOINT", "http://localhost:4318")
  
  ## Usage
  
      alias StellarCore.Observability.Tracer
      
      Tracer.with_span "process_command" do
        # Your code here
      end
      
      Tracer.with_span "fetch_tle", %{source: "celestrak", norad_id: 12345} do
        # Your code here
      end
  """

  require OpenTelemetry.Tracer, as: OtelTracer
  require OpenTelemetry.Span

  @doc """
  Wraps code in a trace span.
  
  ## Parameters
  - name: The span name
  - attributes: Optional map of attributes to attach to the span
  - fun: The function to execute within the span
  
  ## Examples
  
      Tracer.with_span("fetch_satellite_data", fn ->
        # fetch data
      end)
      
      Tracer.with_span("process_conjunction", %{severity: "high"}, fn ->
        # process conjunction
      end)
  """
  defmacro with_span(name, attributes \\ %{}, do: block) do
    quote do
      require OpenTelemetry.Tracer, as: OtelTracer
      
      OtelTracer.with_span unquote(name), %{attributes: map_to_attributes(unquote(attributes))} do
        try do
          result = unquote(block)
          OpenTelemetry.Span.set_status(OpenTelemetry.Tracer.current_span_ctx(), :ok, "")
          result
        rescue
          e ->
            ctx = OpenTelemetry.Tracer.current_span_ctx()
            OpenTelemetry.Span.set_status(ctx, :error, Exception.message(e))
            OpenTelemetry.Span.record_exception(ctx, e, __STACKTRACE__)
            reraise e, __STACKTRACE__
        end
      end
    end
  end

  @doc """
  Adds attributes to the current span.
  """
  def set_attributes(attributes) when is_map(attributes) do
    ctx = OpenTelemetry.Tracer.current_span_ctx()
    OpenTelemetry.Span.set_attributes(ctx, map_to_attributes(attributes))
  end

  @doc """
  Sets the status of the current span.
  """
  def set_status(:ok), do: set_status(:ok, "")
  def set_status(:error, message) do
    ctx = OpenTelemetry.Tracer.current_span_ctx()
    OpenTelemetry.Span.set_status(ctx, :error, message)
  end
  def set_status(:ok, message) do
    ctx = OpenTelemetry.Tracer.current_span_ctx()
    OpenTelemetry.Span.set_status(ctx, :ok, message)
  end

  @doc """
  Adds an event to the current span.
  """
  def add_event(name, attributes \\ %{}) do
    ctx = OpenTelemetry.Tracer.current_span_ctx()
    OpenTelemetry.Span.add_event(ctx, name, map_to_attributes(attributes))
  end

  @doc """
  Records an exception in the current span.
  """
  def record_exception(exception, stacktrace \\ nil) do
    ctx = OpenTelemetry.Tracer.current_span_ctx()
    OpenTelemetry.Span.record_exception(ctx, exception, stacktrace || [])
    OpenTelemetry.Span.set_status(ctx, :error, Exception.message(exception))
  end

  # ============================================================================
  # Domain-Specific Span Helpers
  # ============================================================================

  @doc """
  Creates a span for satellite operations.
  """
  defmacro satellite_span(satellite_id, operation, do: block) do
    quote do
      require OpenTelemetry.Tracer, as: OtelTracer
      
      OtelTracer.with_span "satellite.#{unquote(operation)}", %{
        attributes: [
          {"satellite.id", unquote(satellite_id)},
          {"service.name", "stellar_core"},
          {"operation.type", unquote(operation)}
        ]
      } do
        unquote(block)
      end
    end
  end

  @doc """
  Creates a span for SSA operations.
  """
  defmacro ssa_span(operation, attributes \\ %{}, do: block) do
    quote do
      require OpenTelemetry.Tracer, as: OtelTracer
      
      attrs = Map.merge(unquote(attributes), %{
        "service.name" => "stellar_core",
        "ssa.operation" => unquote(operation)
      })
      
      OtelTracer.with_span "ssa.#{unquote(operation)}", %{
        attributes: map_to_attributes(attrs)
      } do
        unquote(block)
      end
    end
  end

  @doc """
  Creates a span for external API calls.
  """
  defmacro http_span(service, method, url, do: block) do
    quote do
      require OpenTelemetry.Tracer, as: OtelTracer
      
      OtelTracer.with_span "http.#{unquote(service)}", %{
        kind: :client,
        attributes: [
          {"http.method", unquote(method)},
          {"http.url", unquote(url)},
          {"peer.service", unquote(service)}
        ]
      } do
        unquote(block)
      end
    end
  end

  @doc """
  Creates a span for database operations.
  """
  defmacro db_span(operation, table, do: block) do
    quote do
      require OpenTelemetry.Tracer, as: OtelTracer
      
      OtelTracer.with_span "db.#{unquote(operation)}", %{
        kind: :client,
        attributes: [
          {"db.system", "postgresql"},
          {"db.operation", unquote(operation)},
          {"db.sql.table", unquote(table)}
        ]
      } do
        unquote(block)
      end
    end
  end

  # ============================================================================
  # Context Propagation
  # ============================================================================

  @doc """
  Extracts trace context from HTTP headers.
  """
  def extract_context(headers) when is_list(headers) do
    :otel_propagator_text_map.extract(headers)
  end

  @doc """
  Injects trace context into HTTP headers.
  """
  def inject_context(headers \\ []) do
    :otel_propagator_text_map.inject(headers)
  end

  @doc """
  Gets the current trace ID as a hex string.
  """
  def current_trace_id do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined -> nil
      ctx -> 
        trace_id = OpenTelemetry.Span.trace_id(ctx)
        if trace_id != 0, do: Integer.to_string(trace_id, 16), else: nil
    end
  end

  @doc """
  Gets the current span ID as a hex string.
  """
  def current_span_id do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined -> nil
      ctx ->
        span_id = OpenTelemetry.Span.span_id(ctx)
        if span_id != 0, do: Integer.to_string(span_id, 16), else: nil
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  @doc false
  def map_to_attributes(map) when is_map(map) do
    Enum.map(map, fn {k, v} -> {to_string(k), format_value(v)} end)
  end
  def map_to_attributes(list) when is_list(list), do: list
  def map_to_attributes(_), do: []

  defp format_value(v) when is_binary(v), do: v
  defp format_value(v) when is_atom(v), do: to_string(v)
  defp format_value(v) when is_number(v), do: v
  defp format_value(v) when is_boolean(v), do: v
  defp format_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_value(v), do: inspect(v)
end
