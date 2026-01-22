defmodule StellarData.SSA do
  @moduledoc """
  Facade module for Space Situational Awareness (SSA) metrics and queries.
  
  Provides unified access to conjunction, COA, space object, and TLE metrics
  for use by monitoring, dashboards, and Prometheus exporters.
  """

  import Ecto.Query
  alias StellarData.Repo
  alias StellarData.Conjunctions.Conjunction
  alias StellarData.COA.CourseOfAction
  alias StellarData.SpaceObjects.SpaceObject

  # ============================================================================
  # Conjunction Metrics
  # ============================================================================

  @doc """
  Counts active conjunctions by severity level.
  """
  def count_conjunctions_by_severity(severity) when is_atom(severity) do
    now = DateTime.utc_now()

    Conjunction
    |> where([c], c.tca > ^now)
    |> where([c], c.severity == ^severity)
    |> where([c], c.status in [:detected, :monitoring, :mitigating])
    |> select([c], count(c.id))
    |> Repo.one() || 0
  end

  @doc """
  Counts conjunctions by status.
  """
  def count_conjunctions_by_status(status) when is_atom(status) do
    Conjunction
    |> where([c], c.status == ^status)
    |> select([c], count(c.id))
    |> Repo.one() || 0
  end

  @doc """
  Gets all active conjunctions with full details.
  """
  def list_active_conjunctions do
    now = DateTime.utc_now()

    Conjunction
    |> where([c], c.tca > ^now)
    |> where([c], c.status in [:detected, :monitoring, :mitigating])
    |> preload([:primary_object, :secondary_object, :satellite])
    |> order_by([c], asc: c.tca)
    |> Repo.all()
  end

  @doc """
  Gets conjunction summary statistics.
  """
  def get_conjunction_summary do
    now = DateTime.utc_now()

    critical =
      Conjunction
      |> where([c], c.tca > ^now and c.severity == :critical)
      |> where([c], c.status in [:detected, :monitoring, :mitigating])
      |> select([c], count(c.id))
      |> Repo.one() || 0

    high =
      Conjunction
      |> where([c], c.tca > ^now and c.severity == :high)
      |> where([c], c.status in [:detected, :monitoring, :mitigating])
      |> select([c], count(c.id))
      |> Repo.one() || 0

    total =
      Conjunction
      |> where([c], c.tca > ^now)
      |> where([c], c.status in [:detected, :monitoring, :mitigating])
      |> select([c], count(c.id))
      |> Repo.one() || 0

    %{
      critical: critical,
      high: high,
      total: total,
      next_tca: get_next_tca()
    }
  end

  defp get_next_tca do
    now = DateTime.utc_now()

    Conjunction
    |> where([c], c.tca > ^now)
    |> where([c], c.status in [:detected, :monitoring, :mitigating])
    |> order_by([c], asc: c.tca)
    |> limit(1)
    |> select([c], c.tca)
    |> Repo.one()
  end

  # ============================================================================
  # Threat Assessment Metrics
  # ============================================================================

  @doc """
  Counts active threats by severity level.
  For now, threats are derived from conjunction severity.
  """
  def count_threats_by_severity(severity) when is_atom(severity) do
    now = DateTime.utc_now()
    # 48-hour threat window
    threat_window = DateTime.add(now, 48 * 3600, :second)

    Conjunction
    |> where([c], c.tca > ^now and c.tca <= ^threat_window)
    |> where([c], c.severity == ^severity)
    |> where([c], c.status in [:detected, :monitoring, :mitigating])
    |> select([c], count(c.id))
    |> Repo.one() || 0
  end

  # ============================================================================
  # COA Metrics
  # ============================================================================

  @doc """
  Counts COAs by status.
  """
  def count_coas_by_status(status) when is_atom(status) do
    CourseOfAction
    |> where([c], c.status == ^status)
    |> select([c], count(c.id))
    |> Repo.one() || 0
  end

  @doc """
  Counts COAs by maneuver type.
  """
  def count_coas_by_type(maneuver_type) when is_atom(maneuver_type) do
    CourseOfAction
    |> where([c], c.coa_type == ^maneuver_type)
    |> select([c], count(c.id))
    |> Repo.one() || 0
  end

  @doc """
  Gets pending COAs requiring immediate attention.
  """
  def list_pending_coas do
    CourseOfAction
    |> where([c], c.status == :pending)
    |> preload([:conjunction, :satellite])
    |> order_by([c], asc: c.decision_deadline)
    |> Repo.all()
  end

  @doc """
  Gets COA summary statistics.
  """
  def get_coa_summary do
    pending = count_coas_by_status(:pending)
    approved = count_coas_by_status(:approved)
    rejected = count_coas_by_status(:rejected)
    executed = count_coas_by_status(:executed)

    %{
      pending: pending,
      approved: approved,
      rejected: rejected,
      executed: executed,
      total: pending + approved + rejected + executed
    }
  end

  # ============================================================================
  # Space Object Metrics
  # ============================================================================

  @doc """
  Counts space objects by type.
  """
  def count_space_objects_by_type(object_type) when is_atom(object_type) do
    SpaceObject
    |> where([o], o.object_type == ^object_type)
    |> select([o], count(o.id))
    |> Repo.one() || 0
  end

  @doc """
  Counts space objects by orbital regime.
  """
  def count_space_objects_by_regime(regime) when is_atom(regime) do
    # Define orbital regime boundaries (altitude in km)
    {min_alt, max_alt} = regime_altitude_bounds(regime)

    SpaceObject
    |> where([o], o.perigee >= ^min_alt and o.perigee <= ^max_alt)
    |> select([o], count(o.id))
    |> Repo.one() || 0
  end

  defp regime_altitude_bounds(:leo), do: {160, 2000}
  defp regime_altitude_bounds(:meo), do: {2000, 35786}
  defp regime_altitude_bounds(:geo), do: {35786, 36000}
  defp regime_altitude_bounds(:heo), do: {36000, 400000}
  defp regime_altitude_bounds(:sso), do: {600, 800}  # Approximate SSO range
  defp regime_altitude_bounds(_), do: {0, 1000000}

  @doc """
  Gets total count of all tracked space objects.
  """
  def count_all_space_objects do
    SpaceObject
    |> select([o], count(o.id))
    |> Repo.one() || 0
  end

  @doc """
  Gets space object summary.
  """
  def get_space_object_summary do
    %{
      total: count_all_space_objects(),
      satellites: count_space_objects_by_type(:satellite),
      debris: count_space_objects_by_type(:debris),
      rocket_bodies: count_space_objects_by_type(:rocket_body),
      unknown: count_space_objects_by_type(:unknown)
    }
  end

  # ============================================================================
  # TLE Metrics
  # ============================================================================

  @doc """
  Gets the average age of TLE data in seconds.
  """
  def get_average_tle_age_seconds do
    now = DateTime.utc_now()

    result =
      SpaceObject
      |> where([o], not is_nil(o.tle_epoch))
      |> select([o], avg(fragment("EXTRACT(EPOCH FROM ? - ?)", ^now, o.tle_epoch)))
      |> Repo.one()

    case result do
      nil -> 0
      %Decimal{} = d -> Decimal.to_float(d)
      age when is_number(age) -> age
    end
  end

  @doc """
  Counts TLEs older than the specified number of days.
  """
  def count_stale_tles(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    cutoff = DateTime.add(DateTime.utc_now(), -days * 24 * 3600, :second)

    SpaceObject
    |> where([o], not is_nil(o.tle_epoch))
    |> where([o], o.tle_epoch < ^cutoff)
    |> select([o], count(o.id))
    |> Repo.one() || 0
  end

  @doc """
  Gets TLE freshness summary.
  """
  def get_tle_summary do
    total =
      SpaceObject
      |> where([o], not is_nil(o.tle_epoch))
      |> select([o], count(o.id))
      |> Repo.one() || 0

    %{
      total_with_tle: total,
      average_age_seconds: get_average_tle_age_seconds(),
      stale_7_days: count_stale_tles(days: 7),
      stale_14_days: count_stale_tles(days: 14)
    }
  end

  # ============================================================================
  # Combined SSA Dashboard Data
  # ============================================================================

  @doc """
  Gets comprehensive SSA dashboard data.
  """
  def get_dashboard_data do
    %{
      conjunctions: get_conjunction_summary(),
      coas: get_coa_summary(),
      space_objects: get_space_object_summary(),
      tle: get_tle_summary(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Gets SSA health status based on current metrics.
  """
  def get_health_status do
    summary = get_conjunction_summary()

    status =
      cond do
        summary.critical > 0 -> :critical
        summary.high > 0 -> :warning
        true -> :healthy
      end

    pending_coas = count_coas_by_status(:pending)
    stale_tles = count_stale_tles(days: 7)

    warnings =
      []
      |> add_warning_if(pending_coas > 5, "Multiple COAs pending review")
      |> add_warning_if(stale_tles > 10, "Many TLEs are outdated")

    %{
      status: status,
      critical_conjunctions: summary.critical,
      high_conjunctions: summary.high,
      pending_coas: pending_coas,
      warnings: warnings
    }
  end

  defp add_warning_if(warnings, true, msg), do: [msg | warnings]
  defp add_warning_if(warnings, false, _msg), do: warnings
end
