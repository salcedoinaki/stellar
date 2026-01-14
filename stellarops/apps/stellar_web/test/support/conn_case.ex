defmodule StellarWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint StellarWeb.Endpoint

      use Phoenix.ConnTest

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import StellarWeb.ConnCase
    end
  end

  setup _tags do
    # Clean up satellites before each test
    for id <- StellarCore.Satellite.list() do
      StellarCore.Satellite.stop(id)
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
