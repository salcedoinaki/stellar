defmodule StellarWeb.UserSocket do
  use Phoenix.Socket

  channel "satellites:*", StellarWeb.SatelliteChannel
  channel "missions:*", StellarWeb.MissionChannel
  channel "alarms:*", StellarWeb.AlarmChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
