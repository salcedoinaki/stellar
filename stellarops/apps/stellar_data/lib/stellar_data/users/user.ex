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
  
  @valid_roles ~w(admin operator analyst viewer)
  
  schema "users" do
    field :email, :string
    field :password_hash, :string
    field :password, :string, virtual: true
    field :role, :string, default: "viewer"
    field :active, :boolean, default: true
    field :tokens_revoked_at, :utc_datetime_usec
    field :last_login_at, :utc_datetime_usec
    field :failed_login_attempts, :integer, default: 0
    field :locked_until, :utc_datetime_usec
    
    timestamps(type: :utc_datetime_usec)
  end
  
  @doc """
  Changeset for user creation.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :role, :active])
    |> validate_required([:email, :password])
    |> validate_email()
    |> validate_password()
    |> validate_inclusion(:role, @valid_roles)
    |> unique_constraint(:email)
    |> hash_password()
  end
  
  @doc """
  Changeset for password update.
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
    |> validate_inclusion(:role, @valid_roles)
  end
  
  @doc """
  Changeset for login tracking.
  """
  def login_changeset(user, attrs) do
    user
    |> cast(attrs, [:last_login_at, :failed_login_attempts, :locked_until])
  end
  
  @doc """
  Changeset for token revocation tracking.
  """
  def token_revocation_changeset(user, attrs) do
    user
    |> cast(attrs, [:tokens_revoked_at])
  end
  
  # Validations
  
  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email address")
    |> validate_length(:email, max: 255)
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
      nil -> changeset
      password ->
        changeset
        |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end
  
  @doc """
  Check if user has a specific role or higher.
  """
  def has_role?(user, required_role) do
    role_level(user.role) >= role_level(to_string(required_role))
  end
  
  @doc """
  Get role hierarchy level.
  """
  def role_level(role) do
    case role do
      "admin" -> 4
      "operator" -> 3
      "analyst" -> 2
      "viewer" -> 1
      _ -> 0
    end
  end
  
  @doc """
  List of valid roles.
  """
  def valid_roles, do: @valid_roles
end
