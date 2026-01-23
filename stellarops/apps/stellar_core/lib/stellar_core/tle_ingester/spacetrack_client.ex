defmodule StellarCore.TLEIngester.SpaceTrackClient do
  @moduledoc """
  HTTP client for fetching TLE data from Space-Track.org.
  
  Space-Track requires authentication and provides comprehensive satellite catalog data.
  Requires SPACE_TRACK_USERNAME and SPACE_TRACK_PASSWORD environment variables.
  """
  
  require Logger
  
  @base_url "https://www.space-track.org"
  @auth_url "#{@base_url}/ajaxauth/login"
  @tle_url "#{@base_url}/basicspacedata/query/class/gp"
  @timeout 60_000
  
  # GenServer for maintaining authenticated session
  use GenServer
  
  defstruct [:cookie, :expires_at, :authenticated]
  
  # ============================================================================
  # Client API
  # ============================================================================
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Fetch TLE data with optional query parameters.
  
  ## Query Options
  - :norad_cat_id - Filter by NORAD catalog ID
  - :object_type - Filter by object type (PAYLOAD, ROCKET BODY, DEBRIS, UNKNOWN)
  - :decay_date - Filter by decay status (null for active)
  - :epoch - Filter by epoch date
  - :limit - Maximum number of results
  - :orderby - Sort order (e.g., "NORAD_CAT_ID asc")
  """
  def fetch(query \\ %{}) do
    GenServer.call(__MODULE__, {:fetch, query}, @timeout)
  end
  
  @doc """
  Fetch TLE for a specific NORAD ID.
  """
  def fetch_by_norad_id(norad_id) do
    fetch(%{norad_cat_id: norad_id})
  end
  
  @doc """
  Fetch latest TLEs for all active satellites.
  """
  def fetch_active(limit \\ 10000) do
    fetch(%{decay_date: "null", limit: limit, orderby: "EPOCH desc"})
  end
  
  @doc """
  Fetch TLEs for debris objects.
  """
  def fetch_debris(limit \\ 5000) do
    fetch(%{object_type: "DEBRIS", limit: limit})
  end
  
  @doc """
  Fetch TLEs for rocket bodies.
  """
  def fetch_rocket_bodies(limit \\ 2000) do
    fetch(%{object_type: "ROCKET BODY", limit: limit})
  end
  
  # ============================================================================
  # GenServer Callbacks
  # ============================================================================
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      cookie: nil,
      expires_at: nil,
      authenticated: false
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:fetch, query}, _from, state) do
    case ensure_authenticated(state) do
      {:ok, new_state} ->
        result = do_fetch(query, new_state.cookie)
        {:reply, result, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  # ============================================================================
  # Private Functions
  # ============================================================================
  
  defp ensure_authenticated(%{authenticated: true, expires_at: expires_at} = state) do
    if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
      {:ok, state}
    else
      do_authenticate()
    end
  end
  
  defp ensure_authenticated(_state) do
    do_authenticate()
  end
  
  defp do_authenticate do
    username = System.get_env("SPACE_TRACK_USERNAME")
    password = System.get_env("SPACE_TRACK_PASSWORD")
    
    if is_nil(username) or is_nil(password) do
      Logger.warning("Space-Track credentials not configured")
      {:error, :missing_credentials}
    else
      Logger.debug("Authenticating with Space-Track")
      
      body = URI.encode_query(%{
        "identity" => username,
        "password" => password
      })
      
      headers = [
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]
      
      case :httpc.request(:post, 
             {String.to_charlist(@auth_url), headers, 'application/x-www-form-urlencoded', body},
             [{:timeout, 30_000}],
             [{:body_format, :binary}, {:full_result, true}]) do
        {:ok, {{_, 200, _}, resp_headers, _body}} ->
          cookie = extract_cookie(resp_headers)
          
          if cookie do
            Logger.info("Space-Track authentication successful")
            {:ok, %__MODULE__{
              cookie: cookie,
              expires_at: DateTime.add(DateTime.utc_now(), 2, :hour),
              authenticated: true
            }}
          else
            {:error, :no_cookie_received}
          end
          
        {:ok, {{_, status, reason}, _headers, body}} ->
          Logger.error("Space-Track auth failed: #{status} #{reason}")
          {:error, {:auth_failed, status, body}}
          
        {:error, reason} ->
          Logger.error("Space-Track auth request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end
  
  defp extract_cookie(headers) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(to_string(key)) == "set-cookie" end)
    |> case do
      {_, value} ->
        value
        |> to_string()
        |> String.split(";")
        |> List.first()
        
      nil ->
        nil
    end
  end
  
  defp do_fetch(query, cookie) do
    url = build_query_url(query)
    Logger.debug("Fetching from Space-Track: #{url}")
    
    headers = [
      {"Cookie", String.to_charlist(cookie)},
      {"Accept", "text/plain"}
    ]
    
    case :httpc.request(:get,
           {String.to_charlist(url), headers},
           [{:timeout, @timeout}],
           [{:body_format, :binary}]) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, body}
        
      {:ok, {{_, status, reason}, _headers, body}} ->
        Logger.warning("Space-Track query failed: #{status} #{reason}")
        {:error, {:http_error, status, body}}
        
      {:error, reason} ->
        Logger.error("Space-Track request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end
  
  defp build_query_url(query) do
    predicates = 
      query
      |> Enum.map(fn {key, value} ->
        key_str = key |> to_string() |> String.upcase()
        "#{key_str}/#{URI.encode(to_string(value))}"
      end)
      |> Enum.join("/")
    
    base = "#{@tle_url}/format/tle"
    
    if predicates == "" do
      base
    else
      "#{base}/#{predicates}"
    end
  end
  
  @doc """
  Check if Space-Track credentials are configured.
  """
  def credentials_configured? do
    !is_nil(System.get_env("SPACE_TRACK_USERNAME")) and
    !is_nil(System.get_env("SPACE_TRACK_PASSWORD"))
  end
end
