defmodule StellarData.Users do
  @moduledoc """
  Users context - handles user management and authentication.
  """
  
  import Ecto.Query
  alias StellarData.Repo
  alias StellarData.Users.User
  
  require Logger
  
  @max_login_attempts 5
  @lockout_duration_minutes 15
  
  # Query functions
  
  @doc """
  Get a user by ID.
  """
  def get_user(id) do
    Repo.get(User, id)
  end
  
  @doc """
  Get a user by ID, raising if not found.
  """
  def get_user!(id) do
    Repo.get!(User, id)
  end
  
  @doc """
  Get a user by email.
  """
  def get_user_by_email(email) do
    email = String.downcase(email)
    Repo.get_by(User, email: email)
  end
  
  @doc """
  List all users.
  """
  def list_users(opts \\ []) do
    User
    |> filter_by_role(opts[:role])
    |> filter_by_active(opts[:active])
    |> order_by([u], desc: u.inserted_at)
    |> Repo.all()
  end
  
  defp filter_by_role(query, nil), do: query
  defp filter_by_role(query, role) do
    where(query, [u], u.role == ^role)
  end
  
  defp filter_by_active(query, nil), do: query
  defp filter_by_active(query, active) do
    where(query, [u], u.active == ^active)
  end
  
  # Authentication
  
  @doc """
  Authenticate a user by email and password.
  
  Returns `{:ok, user}` on success, or `{:error, reason}` on failure.
  """
  def authenticate(email, password) do
    user = get_user_by_email(email)
    
    cond do
      is_nil(user) ->
        # Perform dummy check to prevent timing attacks
        Argon2.no_user_verify()
        {:error, :user_not_found}
      
      not user.active ->
        {:error, :account_disabled}
      
      locked?(user) ->
        {:error, :account_locked}
      
      Argon2.verify_pass(password, user.password_hash) ->
        # Successful login - reset failed attempts
        {:ok, _} = update_login_success(user)
        {:ok, user}
      
      true ->
        # Failed login - increment attempts
        {:ok, _} = update_login_failure(user)
        {:error, :invalid_credentials}
    end
  end
  
  defp locked?(user) do
    case user.locked_until do
      nil -> false
      locked_until -> DateTime.compare(locked_until, DateTime.utc_now()) == :gt
    end
  end
  
  defp update_login_success(user) do
    user
    |> User.login_changeset(%{
      last_login_at: DateTime.utc_now(),
      failed_login_attempts: 0,
      locked_until: nil
    })
    |> Repo.update()
  end
  
  defp update_login_failure(user) do
    attempts = (user.failed_login_attempts || 0) + 1
    
    locked_until =
      if attempts >= @max_login_attempts do
        DateTime.add(DateTime.utc_now(), @lockout_duration_minutes, :minute)
      else
        nil
      end
    
    user
    |> User.login_changeset(%{
      failed_login_attempts: attempts,
      locked_until: locked_until
    })
    |> Repo.update()
  end
  
  @doc """
  Verify a user's password.
  """
  def verify_password(user, password) do
    if Argon2.verify_pass(password, user.password_hash) do
      {:ok, user}
    else
      {:error, :invalid_password}
    end
  end
  
  # User management
  
  @doc """
  Create a new user.
  """
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
    |> log_result("User created")
  end
  
  @doc """
  Update a user's profile.
  """
  def update_user(user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
    |> log_result("User updated")
  end
  
  @doc """
  Update a user's password.
  """
  def update_password(user, new_password) do
    user
    |> User.password_changeset(%{password: new_password})
    |> Repo.update()
    |> log_result("Password changed")
  end
  
  @doc """
  Update a user's role.
  """
  def update_role(user, role) do
    user
    |> User.role_changeset(%{role: role})
    |> Repo.update()
    |> log_result("Role updated")
  end
  
  @doc """
  Deactivate a user.
  """
  def deactivate_user(user) do
    user
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
    |> log_result("User deactivated")
  end
  
  @doc """
  Activate a user.
  """
  def activate_user(user) do
    user
    |> Ecto.Changeset.change(active: true, failed_login_attempts: 0, locked_until: nil)
    |> Repo.update()
    |> log_result("User activated")
  end
  
  @doc """
  Delete a user.
  """
  def delete_user(user) do
    Repo.delete(user)
    |> log_result("User deleted")
  end
  
  # Authorization helpers
  
  @doc """
  Check if user has at least the specified role.
  """
  def has_role?(user, role) do
    User.has_role?(user, role)
  end
  
  @doc """
  Check if user has a specific permission.
  
  Permission mappings:
  - :manage_users -> admin only
  - :select_coa -> operator+
  - :create_mission -> operator+
  - :classify_threat -> analyst+
  - :view_dashboard -> viewer+ (any authenticated user)
  """
  def can?(user, permission) do
    case permission do
      :manage_users -> user.role == "admin"
      :select_coa -> has_role?(user, :operator)
      :create_mission -> has_role?(user, :operator)
      :classify_threat -> has_role?(user, :analyst)
      :view_dashboard -> has_role?(user, :viewer)
      :ingest_tle -> has_role?(user, :analyst)
      :acknowledge_alarm -> has_role?(user, :operator)
      :resolve_alarm -> has_role?(user, :operator)
      _ -> false
    end
  end
  
  # Private helpers
  
  defp log_result({:ok, user} = result, action) do
    Logger.info(action, user_id: user.id, email: user.email)
    result
  end
  
  defp log_result({:error, changeset} = result, action) do
    Logger.warning("#{action} failed", errors: inspect(changeset.errors))
    result
  end
end
