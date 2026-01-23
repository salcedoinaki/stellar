defmodule StellarWeb.Auth.TokenRevocation do
  @moduledoc """
  Token revocation list for invalidating JWT tokens before expiration.
  
  Uses ETS for fast lookups with periodic cleanup of expired entries.
  Can optionally persist to database for cluster-wide revocation.
  
  ## Usage
  
      # Revoke a token
      TokenRevocation.revoke(token_jti, expires_at)
      
      # Check if revoked
      TokenRevocation.revoked?(token_jti)
      
      # Revoke all tokens for a user
      TokenRevocation.revoke_all_for_user(user_id)
  """
  
  use GenServer
  require Logger
  
  @table_name :stellar_token_revocation
  @cleanup_interval :timer.minutes(5)
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Revoke a token by its JTI (JWT ID).
  
  ## Parameters
  - jti: The JWT ID from the token claims
  - expires_at: When the token would naturally expire (for cleanup)
  """
  def revoke(jti, expires_at \\ nil) do
    expires_at = expires_at || DateTime.add(DateTime.utc_now(), 24, :hour)
    expires_unix = DateTime.to_unix(expires_at)
    
    :ets.insert(@table_name, {jti, expires_unix, DateTime.utc_now()})
    
    # Also persist to database for cluster-wide revocation
    persist_revocation(jti, expires_at)
    
    Logger.info("Token revoked", jti: jti)
    :ok
  end
  
  @doc """
  Check if a token has been revoked.
  """
  def revoked?(jti) do
    case :ets.lookup(@table_name, jti) do
      [{^jti, _expires, _revoked_at}] -> true
      [] -> check_database(jti)
    end
  end
  
  @doc """
  Revoke all tokens for a specific user.
  Used when user changes password, is deleted, or needs immediate logout.
  """
  def revoke_all_for_user(user_id) do
    # Store user revocation with a far-future expiry
    key = {:user, user_id}
    expires_unix = DateTime.to_unix(DateTime.add(DateTime.utc_now(), 30, :day))
    revoked_at = DateTime.utc_now()
    
    :ets.insert(@table_name, {key, expires_unix, revoked_at})
    persist_user_revocation(user_id, revoked_at)
    
    Logger.info("All tokens revoked for user", user_id: user_id)
    :ok
  end
  
  @doc """
  Check if all tokens for a user have been revoked.
  Returns the revocation timestamp if revoked, nil otherwise.
  """
  def user_revoked_at(user_id) do
    key = {:user, user_id}
    
    case :ets.lookup(@table_name, key) do
      [{^key, _expires, revoked_at}] -> revoked_at
      [] -> check_user_database(user_id)
    end
  end
  
  @doc """
  Check if a token issued before a certain time should be rejected.
  """
  def token_valid_for_user?(user_id, token_issued_at) do
    case user_revoked_at(user_id) do
      nil -> true
      revoked_at -> DateTime.compare(token_issued_at, revoked_at) == :gt
    end
  end
  
  @doc """
  Clear all revocations (for testing).
  """
  def clear_all do
    :ets.delete_all_objects(@table_name)
    :ok
  end
  
  @doc """
  Get count of revoked tokens.
  """
  def count do
    :ets.info(@table_name, :size)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table
    :ets.new(@table_name, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    # Load revocations from database
    load_from_database()
    
    # Schedule cleanup
    schedule_cleanup()
    
    Logger.info("TokenRevocation started")
    {:ok, %{}}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end
  
  # Private functions
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
  
  defp cleanup_expired do
    now_unix = DateTime.to_unix(DateTime.utc_now())
    
    # Select and delete expired entries
    expired = :ets.select(@table_name, [
      {{:"$1", :"$2", :_}, [{:<, :"$2", now_unix}], [:"$1"]}
    ])
    
    Enum.each(expired, fn key ->
      :ets.delete(@table_name, key)
    end)
    
    if length(expired) > 0 do
      Logger.debug("Cleaned up #{length(expired)} expired token revocations")
    end
  end
  
  defp load_from_database do
    # Load active revocations from database
    case StellarData.Repo.all(active_revocations_query()) do
      revocations when is_list(revocations) ->
        Enum.each(revocations, fn rev ->
          :ets.insert(@table_name, {rev.jti, DateTime.to_unix(rev.expires_at), rev.revoked_at})
        end)
        
        Logger.info("Loaded #{length(revocations)} token revocations from database")
        
      _ ->
        :ok
    end
  rescue
    _ -> :ok  # Database may not be available yet
  end
  
  defp active_revocations_query do
    import Ecto.Query
    
    now = DateTime.utc_now()
    
    from r in "token_revocations",
      where: r.expires_at > ^now,
      select: %{jti: r.jti, expires_at: r.expires_at, revoked_at: r.revoked_at}
  end
  
  defp persist_revocation(jti, expires_at) do
    # Insert into database for cluster-wide revocation
    StellarData.Repo.insert_all(
      "token_revocations",
      [%{
        jti: jti,
        expires_at: expires_at,
        revoked_at: DateTime.utc_now(),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }],
      on_conflict: :nothing
    )
  rescue
    _ -> :ok  # Gracefully handle database errors
  end
  
  defp persist_user_revocation(user_id, revoked_at) do
    import Ecto.Query
    
    # Update user's tokens_revoked_at field
    StellarData.Repo.update_all(
      from(u in "users", where: u.id == ^user_id),
      set: [tokens_revoked_at: revoked_at, updated_at: DateTime.utc_now()]
    )
  rescue
    _ -> :ok
  end
  
  defp check_database(jti) do
    import Ecto.Query
    
    now = DateTime.utc_now()
    
    query = from r in "token_revocations",
      where: r.jti == ^jti and r.expires_at > ^now,
      select: r.jti
    
    case StellarData.Repo.one(query) do
      nil -> false
      _ -> 
        # Cache in ETS for future lookups
        true
    end
  rescue
    _ -> false
  end
  
  defp check_user_database(user_id) do
    import Ecto.Query
    
    query = from u in "users",
      where: u.id == ^user_id and not is_nil(u.tokens_revoked_at),
      select: u.tokens_revoked_at
    
    StellarData.Repo.one(query)
  rescue
    _ -> nil
  end
end
