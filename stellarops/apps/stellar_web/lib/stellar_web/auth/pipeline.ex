defmodule StellarWeb.Auth.Pipeline do
  @moduledoc """
  Guardian authentication pipelines for the StellarOps API.
  """

  use Guardian.Plug.Pipeline,
    otp_app: :stellar_web,
    module: StellarWeb.Auth.Guardian,
    error_handler: StellarWeb.Auth.ErrorHandler

  # Verify the token in the session or header
  plug Guardian.Plug.VerifySession, claims: %{"typ" => "access"}
  plug Guardian.Plug.VerifyHeader, claims: %{"typ" => "access"}

  # Load the user if a token was found
  plug Guardian.Plug.LoadResource, allow_blank: true
end

defmodule StellarWeb.Auth.EnsureAuthenticated do
  @moduledoc """
  Pipeline that ensures a user is authenticated.
  """

  use Guardian.Plug.Pipeline,
    otp_app: :stellar_web,
    module: StellarWeb.Auth.Guardian,
    error_handler: StellarWeb.Auth.ErrorHandler

  plug Guardian.Plug.EnsureAuthenticated
end

defmodule StellarWeb.Auth.EnsureRole do
  @moduledoc """
  Plug that ensures a user has a specific role.
  """

  import Plug.Conn
  alias StellarData.Users

  def init(opts), do: opts

  def call(conn, opts) do
    required_role = Keyword.get(opts, :role, :viewer)
    user = Guardian.Plug.current_resource(conn)

    if user && Users.has_role?(user, required_role) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.put_view(StellarWeb.ErrorJSON)
      |> Phoenix.Controller.render("403.json")
      |> halt()
    end
  end
end

defmodule StellarWeb.Auth.EnsurePermission do
  @moduledoc """
  Plug that ensures a user has a specific permission.
  """

  import Plug.Conn
  alias StellarData.Users

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.get(opts, :action)
    user = Guardian.Plug.current_resource(conn)

    if user && Users.can?(user, action) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.put_view(StellarWeb.ErrorJSON)
      |> Phoenix.Controller.render("403.json")
      |> halt()
    end
  end
end
