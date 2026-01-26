defmodule StellarCore.TLEIngester.CelesTrakClient do
  @moduledoc """
  HTTP client for fetching TLE data from CelesTrak.
  
  CelesTrak provides free access to TLE data for various satellite categories.
  Base URL: https://celestrak.org/NORAD/elements/gp.php
  """
  
  require Logger
  
  @base_url "https://celestrak.org/NORAD/elements/gp.php"
  @timeout 30_000
  
  @category_mapping %{
    active: "active",
    debris: "cosmos-2251-debris",
    iridium_debris: "iridium-33-debris",
    rocket_bodies: "1999-025",
    stations: "stations",
    weather: "weather",
    noaa: "noaa",
    goes: "goes",
    resource: "resource",
    sarsat: "sarsat",
    dmc: "dmc",
    tdrss: "tdrss",
    argos: "argos",
    planet: "planet",
    spire: "spire",
    geo: "geo",
    intelsat: "intelsat",
    ses: "ses",
    iridium: "iridium",
    iridium_next: "iridium-NEXT",
    starlink: "starlink",
    oneweb: "oneweb",
    orbcomm: "orbcomm",
    globalstar: "globalstar",
    swarm: "swarm",
    amateur: "amateur",
    x_comm: "x-comm",
    other_comm: "other-comm",
    satnogs: "satnogs",
    gorizont: "gorizont",
    raduga: "raduga",
    molniya: "molniya",
    gnss: "gnss",
    gps_ops: "gps-ops",
    glo_ops: "glo-ops",
    galileo: "galileo",
    beidou: "beidou",
    sbas: "sbas",
    nnss: "nnss",
    musson: "musson",
    science: "science",
    geodetic: "geodetic",
    engineering: "engineering",
    education: "education",
    military: "military",
    radar: "radar",
    cubesat: "cubesat",
    other: "other",
    supplemental_tle: "supplemental/sup-gp.php"
  }
  
  @doc """
  Fetch TLE data for a specific category.
  
  ## Categories
  - :active - Active satellites
  - :debris - Debris from Cosmos-2251 collision
  - :rocket_bodies - Rocket bodies
  - :starlink - Starlink constellation
  - :oneweb - OneWeb constellation
  - :gnss - Navigation satellites
  - ... and many more
  
  Returns {:ok, tle_text} or {:error, reason}
  """
  def fetch(category) when is_atom(category) do
    case Map.get(@category_mapping, category) do
      nil ->
        {:error, {:unknown_category, category}}
        
      group ->
        url = build_url(group)
        do_fetch(url)
    end
  end
  
  @doc """
  Fetch TLE by NORAD catalog number.
  """
  def fetch_by_norad_id(norad_id) when is_integer(norad_id) do
    url = "#{@base_url}?CATNR=#{norad_id}&FORMAT=TLE"
    do_fetch(url)
  end
  
  @doc """
  Fetch TLEs for a list of NORAD catalog numbers.
  """
  def fetch_by_norad_ids(norad_ids) when is_list(norad_ids) do
    # CelesTrak allows comma-separated CATNR
    ids_str = norad_ids |> Enum.map(&to_string/1) |> Enum.join(",")
    url = "#{@base_url}?CATNR=#{ids_str}&FORMAT=TLE"
    do_fetch(url)
  end
  
  @doc """
  Search for satellites by name.
  """
  def search_by_name(name) when is_binary(name) do
    url = "#{@base_url}?NAME=#{URI.encode(name)}&FORMAT=TLE"
    do_fetch(url)
  end
  
  defp build_url(group) do
    "#{@base_url}?GROUP=#{group}&FORMAT=TLE"
  end
  
  defp do_fetch(url) do
    Logger.debug("Fetching TLE from CelesTrak: #{url}")
    
    headers = [
      {~c"User-Agent", ~c"StellarOps/1.0"},
      {~c"Accept", ~c"text/plain"}
    ]
    
    http_opts = [
      {:timeout, @timeout}, 
      {:connect_timeout, 10_000},
      {:ssl, [
        {:verify, :verify_none}
      ]}
    ]
    
    case :httpc.request(:get, {String.to_charlist(url), headers}, http_opts, [{:body_format, :binary}]) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        # Ensure body is binary (httpc can return charlist)
        body_binary = if is_list(body), do: :erlang.list_to_binary(body), else: body
        Logger.debug("CelesTrak returned #{byte_size(body_binary)} bytes")
        {:ok, body_binary}
        
      {:ok, {{_, 204, _}, _headers, _body}} ->
        {:ok, ""}  # No content (empty category)
        
      {:ok, {{_, status, reason}, _headers, body}} ->
        Logger.warning("CelesTrak returned #{status}: #{inspect(reason)}")
        {:error, {:http_error, status, body}}
        
      {:error, reason} ->
        Logger.error("CelesTrak request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end
  
  @doc """
  List all available categories.
  """
  def available_categories do
    Map.keys(@category_mapping)
  end
end
