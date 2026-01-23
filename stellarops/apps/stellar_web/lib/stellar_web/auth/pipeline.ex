defmodule StellarWeb.Auth.Pipeline do
  @moduledoc """
  Guardian authentication pipeline.
  
  Provides plugs for:
  - Optional authentication (load user if token present)
  - Required authentication (reject if no valid token)
  - Role-based authorization
  """
  
  use Guardian.Plug.Pipeline,
    otp_app: :stellar_web,
    module: StellarWeb.Auth.Guardian,
    error_handler: StellarWeb.Auth.ErrorHandler
  
  # Load resource if token is present (doesn't reject if missing)
  plug Guardian.Plug.VerifyHeader, claims: %{typ: "access"}
  plug Guardian.Plug.LoadResource, allow_blank: true
end

defmodule StellarWeb.Auth.AuthenticatedPipeline do
  @moduledoc """
  Pipeline that requires authentication.
  """
  
  use Guardian.Plug.Pipeline,
    otp_app: :stellar_web,
    module: StellarWeb.Auth.Guardian,
    error_handler: StellarWeb.Auth.ErrorHandler
  
  plug Guardian.Plug.VerifyHeader, claims: %{typ: "access"}
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource
end

defmodule StellarWeb.Auth.EnsureRole do
  @moduledoc """
  Plug to ensure user has required role.
  
  Role hierarchy: admin > operator > analyst > viewer
  
  ## Usage
  
      plug EnsureRole, :operator  # Requires operator or higher
      plug EnsureRole, [:admin, :operator]  # Requires one of these roles
  """
  
  import Plug.Conn
  import Phoenix.Controller
  
  alias StellarWeb.Auth.Guardian
  
  @role_hierarchy %{
    "admin" => 4,
    "operator" => 3,
    "analyst" => 2,
    "viewer" => 1
  }
  
  def init(opts), do: opts
  
  def call(conn, required_role) when is_atom(required_role) do
    call(conn, [required_role])
  end
  
  def call(conn, required_roles) when is_list(required_roles) do
    user = Guardian.Plug.current_resource(conn)
    
    if user && has_required_role?(user, required_roles) do
      conn
    else
      log_authorization_failure(conn, user, required_roles)
      
      conn
      |> put_status(:forbidden)
      |> put_view(json: StellarWeb.ErrorJSON)
      |> render(:error, %{message: "Insufficient permissions", required_roles: required_roles})
      |> halt()
    end
  end
  
  defp has_required_role?(user, required_roles) do
    user_level = @role_hierarchy[user.role] || 0
    
    Enum.any?(required_roles, fn role ->
      required_level = @role_hierarchy[to_string(role)] || 0
      user_level >= required_level
    end)
  end
  
  defp log_authorization_failure(conn, user, required_roles) do
    require Logger
    
    Logger.warning("Authorization failure",
      path: conn.request_path,
      method: conn.method,
      user_id: user && user.id,
      user_role: user && user.role,
      required_roles: required_roles,
      remote_ip: conn.remote_ip |> :inet.ntoa() |> to_string()
    )
  end
end

defmodule StellarWeb.Auth.EnsurePermission do
  @moduledoc """
  Plug to ensure user has specific permission.
  
  Permissions are more granular than roles.
  
  ## Usage
  
      plug EnsurePermission, :manage_users
      plug EnsurePermission, :select_coa
  """
  
  import Plug.Conn
  import Phoenix.Controller
  
  alias StellarWeb.Auth.Guardian
  alias StellarData.Users
  
  def init(opts), do: opts
  
  def call(conn, permission) when is_atom(permission) do
    user = Guardian.Plug.current_resource(conn)
    
    if user && Users.can?(user, permission) do
      conn
    else
      log_permission_failure(conn, user, permission)
      
      conn
      |> put_status(:forbidden)
      |> put_view(json: StellarWeb.ErrorJSON)
      |> render(:error, %{message: "Permission denied", required_permission: permission})
      |> halt()
    end
  end
  
  defp log_permission_failure(conn, user, permission) do
    require Logger
    
    Logger.warning("Permission denied",
      path: conn.request_path,
      method: conn.method,
      user_id: user && user.id,
      user_role: user && user.role,
      required_permission: permission,
      remote_ip: conn.remote_ip |> :inet.ntoa() |> to_string()
    )
  end
end
