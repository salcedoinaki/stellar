defmodule StellarData.Users.User do
  @moduledoc """
  User schema for authentication and authorization.
  
  ## Roles
  
  - `admin`: Full system access, user management
  - `operator`: Mission control, COA selection, satellite operations
  - `analyst`: Threat analysis, classification, intel ingestion
  - `viewer`: Read-only access to dashboards and data
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles [:admin, :operator, :analyst, :viewer]

  schema "users" do
    field :email, :string
    field :password_hash, :string
    field :password, :string, virtual: true
    field :name, :string
    field :role, Ecto.Enum, values: @roles, default: :viewer
    field :active, :boolean, default: true
    field :tokens_revoked_at, :utc_datetime_usec
    field :last_login_at, :utc_datetime_usec
    field :failed_login_attempts, :integer, default: 0
    field :locked_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Registration changeset for creating new users.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :name, :role])
    |> validate_required([:email, :password, :name])
    |> validate_email()
    |> validate_password()
    |> unique_constraint(:email)
    |> hash_password()
  end

  @doc """
  Changeset for updating user profile.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :role, :active, :metadata])
    |> validate_required([:name])
  end

  @doc """
  Changeset for updating password.
  """
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
    |> hash_password()
  end

  @doc """
  Changeset for role update.
  """
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
  end

  @doc """
  Records a successful login.
  """
  def login_changeset(user) do
    user
    |> change(%{
      last_login_at: DateTime.utc_now(),
      failed_login_attempts: 0,
      locked_at: nil
    })
  end

  @doc """
  Records a failed login attempt.
  """
  def failed_login_changeset(user) do
    attempts = (user.failed_login_attempts || 0) + 1
    locked_at = if attempts >= 5, do: DateTime.utc_now(), else: user.locked_at

    user
    |> change(%{
      failed_login_attempts: attempts,
      locked_at: locked_at
    })
  end

  @doc """
  Changeset for token revocation tracking.
  """
  def token_revocation_changeset(user, attrs) do
    user
    |> cast(attrs, [:tokens_revoked_at])
  end

  @doc """
  Validates a password against the stored hash.
  """
  def valid_password?(%__MODULE__{password_hash: hash}, password) 
      when is_binary(hash) and is_binary(password) do
    Bcrypt.verify_pass(password, hash)
  end

  def valid_password?(_, _), do: Bcrypt.no_user_verify()

  @doc """
  Checks if the user account is locked.
  """
  def locked?(%__MODULE__{locked_at: nil}), do: false
  def locked?(%__MODULE__{locked_at: locked_at}) do
    # Accounts unlock after 30 minutes
    DateTime.diff(DateTime.utc_now(), locked_at, :minute) < 30
  end

  @doc """
  Check if user has a specific role or higher.
  """
  def has_role?(user, required_role) do
    role_level(user.role) >= role_level(required_role)
  end

  @doc """
  Get role hierarchy level.
  """
  def role_level(role) do
    case role do
      :admin -> 4
      :operator -> 3
      :analyst -> 2
      :viewer -> 1
      "admin" -> 4
      "operator" -> 3
      "analyst" -> 2
      "viewer" -> 1
      _ -> 0
    end
  end

  @doc """
  Returns the list of available roles.
  """
  def roles, do: @roles

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email address")
    |> validate_length(:email, max: 160)
    |> update_change(:email, &String.downcase/1)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 72, message: "must be between 8 and 72 characters")
    |> validate_format(:password, ~r/[a-z]/, message: "must contain at least one lowercase letter")
    |> validate_format(:password, ~r/[A-Z]/, message: "must contain at least one uppercase letter")
    |> validate_format(:password, ~r/[0-9]/, message: "must contain at least one digit")
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:password_hash, Bcrypt.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end
end
