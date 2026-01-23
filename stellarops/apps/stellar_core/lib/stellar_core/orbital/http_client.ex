defmodule StellarCore.Orbital.HttpClient do
  @moduledoc """
  HTTP client for the Rust Orbital Service.
  
  Uses Req with Finch for connection pooling and retries.
  """

  require Logger

  @timeout 10_000
  @retry_max_attempts 3
  @retry_delay 200

  @doc """
  Initialize the HTTP client pool.
  Called from the application supervisor.
  """
  def child_spec(_opts) do
    Finch.child_spec(
      name: __MODULE__.Finch,
      pools: %{
        default: [size: 25, count: 5]
      }
    )
  end

  @doc """
  Make a GET request to the orbital service.
  """
  def get(path, opts \\ []) do
    url = build_url(path)

    request_opts =
      [
        method: :get,
        url: url,
        finch: __MODULE__.Finch,
        receive_timeout: opts[:timeout] || @timeout,
        retry: retry_opts()
      ]

    make_request(request_opts)
  end

  @doc """
  Make a POST request to the orbital service.
  """
  def post(path, body, opts \\ []) do
    url = build_url(path)

    request_opts =
      [
        method: :post,
        url: url,
        json: body,
        finch: __MODULE__.Finch,
        receive_timeout: opts[:timeout] || @timeout,
        retry: retry_opts()
      ]

    make_request(request_opts)
  end

  # Private functions

  defp build_url(path) do
    base_url = orbital_service_url()
    "#{base_url}#{path}"
  end

  defp orbital_service_url do
    case System.get_env("ORBITAL_SERVICE_URL") do
      nil ->
        # Parse from ORBITAL_SERVICE_HOST (which may include gRPC port)
        host = System.get_env("ORBITAL_SERVICE_HOST", "orbital:50051")

        # Extract just the hostname, use HTTP port
        hostname =
          host
          |> String.split(":")
          |> List.first()

        http_port = System.get_env("ORBITAL_HTTP_PORT", "9090")
        "http://#{hostname}:#{http_port}"

      url ->
        url
    end
  end

  defp retry_opts do
    [
      max_attempts: @retry_max_attempts,
      delay: @retry_delay,
      retry: :transient
    ]
  end

  defp make_request(opts) do
    case Req.request(opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} when status >= 400 ->
        Logger.warning("Orbital service returned #{status}: #{inspect(body)}")
        
        error_msg =
          case body do
            %{"error" => error} -> error
            %{"error_message" => error} -> error
            _ -> "HTTP #{status}"
          end

        {:error, {:http_error, status, error_msg}}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        Logger.warning("Failed to connect to orbital service at #{inspect(opts[:url])}")
        {:error, :connection_refused}

      {:error, %Req.TransportError{reason: :timeout}} ->
        Logger.warning("Request to orbital service timed out")
        {:error, :timeout}

      {:error, exception} ->
        Logger.error("Orbital service request failed: #{inspect(exception)}")
        {:error, {:request_failed, exception}}
    end
  end
end
