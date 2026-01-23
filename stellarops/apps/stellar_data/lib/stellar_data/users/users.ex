defmodule StellarData.Users do
  @moduledoc """
  Context module for user management and authentication.
  """

  import Ecto.Query
  alias StellarData.Repo
  alias StellarData.Users.User

  require Logger

  @max_login_attempts 5
  @lockout_duration_minutes 30

  # ============================================================================
  # User CRUD
  # ============================================================================

  @doc """
  Lists all users with optional filtering.
  """
  def list_users(opts \\ []) do
    User
    |> filter_by_role(Keyword.get(opts, :role))
    |> filter_by_active(Keyword.get(opts, :active))
    |> order_by([u], asc: u.name)
    |> Repo.all()
  end

  @doc """
  Gets a user by ID.
  """
  def get_user(id) do
    Repo.get(User, id)
  end

  @doc """
  Gets a user by ID, raising if not found.
  """
  def get_user!(id) do
    Repo.get!(User, id)
  end

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    User
    |> where([u], u.email == ^String.downcase(email))
    |> Repo.one()
  end

  @doc """
  Creates a new user.
  """
  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
    |> log_result("User created")
  end

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
    |> log_result("User updated")
  end

  @doc """
  Updates a user's password.
  """
  def update_user_password(%User{} = user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Repo.update()
    |> log_result("Password changed")
  end

  @doc """
  Updates a user's role.
  """
  def update_role(%User{} = user, role) do
    user
    |> User.role_changeset(%{role: role})
    |> Repo.update()
    |> log_result("Role updated")
  end

  @doc """
  Deletes a user.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
    |> log_result("User deleted")
  end

  @doc """
  Deactivates a user instead of deleting.
  """
  def deactivate_user(%User{} = user) do
    update_user(user, %{active: false})
    |> log_result("User deactivated")
  end

  @doc """
  Activates a user.
  """
  def activate_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(active: true, failed_login_attempts: 0, locked_at: nil)
    |> Repo.update()
    |> log_result("User activated")
  end

  # ============================================================================
  # Authentication
  # ============================================================================

  @doc """
  Authenticates a user by email and password.
  
  Returns `{:ok, user}` on success, or `{:error, reason}` on failure.
  """
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    cond do
      is_nil(user) ->
        # Prevent timing attacks
        Argon2.no_user_verify()
        {:error, :invalid_credentials}

      not user.active ->
        {:error, :account_disabled}

      User.locked?(user) ->
        {:error, :account_locked}

      User.valid_password?(user, password) ->
        record_login(user)
        {:ok, user}

      true ->
        record_failed_login(user)
        {:error, :invalid_credentials}
    end
  end

  @doc """
  Verify a user's password.
  """
  def verify_password(%User{} = user, password) do
    if User.valid_password?(user, password) do
      {:ok, user}
    else
      {:error, :invalid_password}
    end
  end

  @doc """
  Records a successful login.
  """
  def record_login(%User{} = user) do
    user
    |> User.login_changeset()
    |> Repo.update()
  end

  @doc """
  Records a failed login attempt.
  """
  def record_failed_login(%User{} = user) do
    user
    |> User.failed_login_changeset()
    |> Repo.update()
  end

  @doc """
  Unlocks a locked user account.
  """
  def unlock_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(%{locked_at: nil, failed_login_attempts: 0})
    |> Repo.update()
    |> log_result("User unlocked")
  end

  # ============================================================================
  # Authorization Helpers
  # ============================================================================

  @doc """
  Checks if a user has a specific role or higher.
  """
  def has_role?(%User{} = user, required_role) do
    User.has_role?(user, required_role)
  end

  @doc """
  Checks if a user can perform a specific action.
  
  Permission mappings:
  - :manage_users -> admin only
  - :manage_system -> admin only
  - :approve_coa / :select_coa -> operator+
  - :manage_missions / :create_mission -> operator+
  - :acknowledge_alarm / :resolve_alarm -> operator+
  - :view_ssa / :classify_threat -> analyst+
  - :ingest_tle -> analyst+
  - :view_dashboard / :view_satellites -> viewer+ (any authenticated user)
  """
  def can?(%User{} = user, action) do
    case action do
      :view_dashboard -> user.active
      :view_satellites -> user.active
      :view_ssa -> user.active and user.role in [:admin, :operator, :analyst]
      :classify_threat -> user.active and user.role in [:admin, :operator, :analyst]
      :ingest_tle -> user.active and user.role in [:admin, :operator, :analyst]
      :approve_coa -> user.active and user.role in [:admin, :operator]
      :select_coa -> user.active and user.role in [:admin, :operator]
      :manage_missions -> user.active and user.role in [:admin, :operator]
      :create_mission -> user.active and user.role in [:admin, :operator]
      :acknowledge_alarm -> user.active and user.role in [:admin, :operator]
      :resolve_alarm -> user.active and user.role in [:admin, :operator]
      :manage_users -> user.active and user.role == :admin
      :manage_system -> user.active and user.role == :admin
      _ -> false
    end
  end

  # ============================================================================
  # Statistics
  # ============================================================================

  @doc """
  Gets user statistics.
  """
  def get_stats do
    total = Repo.aggregate(User, :count)
    active = Repo.aggregate(from(u in User, where: u.active), :count)
    
    by_role =
      User
      |> group_by([u], u.role)
      |> select([u], {u.role, count(u.id)})
      |> Repo.all()
      |> Enum.into(%{})

    %{
      total: total,
      active: active,
      inactive: total - active,
      by_role: by_role
    }
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp filter_by_role(query, nil), do: query
  defp filter_by_role(query, role), do: where(query, [u], u.role == ^role)

  defp filter_by_active(query, nil), do: query
  defp filter_by_active(query, active), do: where(query, [u], u.active == ^active)

  defp log_result({:ok, user} = result, action) do
    Logger.info(action, user_id: user.id, email: user.email)
    result
  end

  defp log_result({:error, changeset} = result, action) do
    Logger.warning("#{action} failed", errors: inspect(changeset.errors))
    result
  end

  defp log_result(result, _action), do: result
end
