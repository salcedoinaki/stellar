defmodule StellarWeb do
  @moduledoc """
  The entrypoint for defining your web interface.

  This module is used by controllers and channels to share common
  functionality.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:json]

      import Plug.Conn
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: StellarWeb.Endpoint,
        router: StellarWeb.Router,
        statics: StellarWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
