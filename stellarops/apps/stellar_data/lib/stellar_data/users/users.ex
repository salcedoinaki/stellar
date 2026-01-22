defmodule StellarData.Users do
  @moduledoc """
  Context module for user management and authentication.
  """

  import Ecto.Query
  alias StellarData.Repo
  alias StellarData.Users.User

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
  end

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a user's password.
  """
  def update_user_password(%User{} = user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Deactivates a user instead of deleting.
  """
  def deactivate_user(%User{} = user) do
    update_user(user, %{active: false})
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
        Bcrypt.no_user_verify()
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
  end

  # ============================================================================
  # Authorization Helpers
  # ============================================================================

  @doc """
  Checks if a user has a specific role or higher.
  """
  def has_role?(%User{role: role}, required_role) do
    role_level(role) >= role_level(required_role)
  end

  @doc """
  Checks if a user can perform a specific action.
  """
  def can?(%User{} = user, action) do
    case action do
      :view_dashboard -> user.active
      :view_satellites -> user.active
      :view_ssa -> user.active and user.role in [:admin, :operator, :analyst]
      :approve_coa -> user.active and user.role in [:admin, :operator]
      :manage_missions -> user.active and user.role in [:admin, :operator]
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

  defp role_level(:admin), do: 4
  defp role_level(:operator), do: 3
  defp role_level(:analyst), do: 2
  defp role_level(:viewer), do: 1
  defp role_level(_), do: 0
end
