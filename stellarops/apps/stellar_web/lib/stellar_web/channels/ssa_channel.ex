defmodule StellarWeb.SSAChannel do
  @moduledoc """
  WebSocket channel for real-time Space Situational Awareness updates.

  Clients can join:
  - `ssa:conjunctions` - receive conjunction detection events
  - `ssa:coa` - receive course of action updates
  - `ssa:threats` - receive threat assessment updates
  - `ssa:satellite:<id>` - receive SSA events for a specific satellite

  Events pushed to clients:
  - conjunction_detected: new conjunction found during screening
  - conjunction_updated: conjunction data updated (status, probability, etc.)
  - coa_generated: new course of action generated
  - coa_approved: COA approved for execution
  - coa_rejected: COA rejected
  - coa_executing: COA execution started
  - threat_updated: threat assessment changed for a space object
  - screening_started: conjunction screening cycle started
  - screening_complete: conjunction screening cycle completed
  """

  use Phoenix.Channel

  alias StellarData.SpaceObjects
  alias StellarData.Conjunctions
  alias StellarData.COA
  alias StellarCore.SSA.ConjunctionDetector
  alias StellarCore.SSA.COAPlanner
  alias Phoenix.PubSub

  @pubsub StellarWeb.PubSub

  # Join handlers

  @impl true
  def join("ssa:conjunctions", _payload, socket) do
    PubSub.subscribe(@pubsub, "ssa:conjunctions")
    send(self(), :after_join_conjunctions)
    {:ok, socket}
  end

  def join("ssa:coa", _payload, socket) do
    PubSub.subscribe(@pubsub, "ssa:coa")
    send(self(), :after_join_coa)
    {:ok, socket}
  end

  def join("ssa:threats", _payload, socket) do
    PubSub.subscribe(@pubsub, "ssa:threats")
    send(self(), :after_join_threats)
    {:ok, socket}
  end

  def join("ssa:satellite:" <> satellite_id, _payload, socket) do
    PubSub.subscribe(@pubsub, "ssa:satellite:#{satellite_id}")
    {:ok, assign(socket, :satellite_id, satellite_id)}
  end

  def join("ssa:all", _payload, socket) do
    PubSub.subscribe(@pubsub, "ssa:conjunctions")
    PubSub.subscribe(@pubsub, "ssa:coa")
    PubSub.subscribe(@pubsub, "ssa:threats")
    send(self(), :after_join_all)
    {:ok, socket}
  end

  # After join handlers

  @impl true
  def handle_info(:after_join_conjunctions, socket) do
    # Send current critical conjunctions
    critical = Conjunctions.list_critical_conjunctions()
    push(socket, "critical_conjunctions", %{
      conjunctions: Enum.map(critical, &serialize_conjunction/1),
      count: length(critical)
    })

    # Send statistics
    stats = Conjunctions.get_statistics()
    push(socket, "conjunction_stats", stats)

    # Send detector status
    status = ConjunctionDetector.get_status()
    push(socket, "detector_status", serialize_detector_status(status))

    {:noreply, socket}
  end

  def handle_info(:after_join_coa, socket) do
    # Send pending COAs
    pending = COA.list_pending_coas()
    push(socket, "pending_coas", %{
      coas: Enum.map(pending, &serialize_coa/1),
      count: length(pending)
    })

    # Send urgent COAs
    urgent = COA.list_urgent_coas(24)
    push(socket, "urgent_coas", %{
      coas: Enum.map(urgent, &serialize_coa/1),
      count: length(urgent)
    })

    {:noreply, socket}
  end

  def handle_info(:after_join_threats, socket) do
    # Send high threat objects
    threats = SpaceObjects.list_high_threat_objects()
    push(socket, "high_threat_objects", %{
      objects: Enum.map(threats, &serialize_space_object/1),
      count: length(threats)
    })

    {:noreply, socket}
  end

  def handle_info(:after_join_all, socket) do
    # Combine all initial data
    critical = Conjunctions.list_critical_conjunctions()
    pending = COA.list_pending_coas()
    threats = SpaceObjects.list_high_threat_objects()
    stats = Conjunctions.get_statistics()
    detector_status = ConjunctionDetector.get_status()

    push(socket, "ssa_summary", %{
      critical_conjunctions: length(critical),
      pending_coas: length(pending),
      high_threat_objects: length(threats),
      conjunction_stats: stats,
      detector_status: serialize_detector_status(detector_status)
    })

    {:noreply, socket}
  end

  # Handle PubSub broadcasts

  @impl true
  def handle_info({:conjunction_detected, conjunction}, socket) do
    push(socket, "conjunction_detected", serialize_conjunction(conjunction))
    {:noreply, socket}
  end

  def handle_info({:conjunction_updated, conjunction}, socket) do
    push(socket, "conjunction_updated", serialize_conjunction(conjunction))
    {:noreply, socket}
  end

  def handle_info({:coa_generated, coas}, socket) when is_list(coas) do
    push(socket, "coa_generated", %{
      coas: Enum.map(coas, &serialize_coa/1),
      count: length(coas)
    })
    {:noreply, socket}
  end

  def handle_info({:coa_generated, coa}, socket) do
    push(socket, "coa_generated", serialize_coa(coa))
    {:noreply, socket}
  end

  def handle_info({:coa_approved, coa}, socket) do
    push(socket, "coa_approved", serialize_coa(coa))
    {:noreply, socket}
  end

  def handle_info({:coa_rejected, coa}, socket) do
    push(socket, "coa_rejected", serialize_coa(coa))
    {:noreply, socket}
  end

  def handle_info({:coa_executing, coa}, socket) do
    push(socket, "coa_executing", serialize_coa(coa))
    {:noreply, socket}
  end

  def handle_info({:threat_updated, object}, socket) do
    push(socket, "threat_updated", serialize_space_object(object))
    {:noreply, socket}
  end

  def handle_info({:screening_started, info}, socket) do
    push(socket, "screening_started", info)
    {:noreply, socket}
  end

  def handle_info({:screening_complete, results}, socket) do
    push(socket, "screening_complete", results)
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Client commands

  @impl true
  def handle_in("get_critical_conjunctions", _payload, socket) do
    critical = Conjunctions.list_critical_conjunctions()
    {:reply, {:ok, %{conjunctions: Enum.map(critical, &serialize_conjunction/1)}}, socket}
  end

  def handle_in("get_pending_coas", _payload, socket) do
    pending = COA.list_pending_coas()
    {:reply, {:ok, %{coas: Enum.map(pending, &serialize_coa/1)}}, socket}
  end

  def handle_in("get_conjunction_stats", _payload, socket) do
    stats = Conjunctions.get_statistics()
    {:reply, {:ok, stats}, socket}
  end

  def handle_in("get_detector_status", _payload, socket) do
    status = ConjunctionDetector.get_status()
    {:reply, {:ok, serialize_detector_status(status)}, socket}
  end

  def handle_in("trigger_screening", _payload, socket) do
    case ConjunctionDetector.run_screening() do
      {:ok, results} -> {:reply, {:ok, results}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("approve_coa", %{"id" => id, "user_id" => user_id, "notes" => notes}, socket) do
    case COA.approve_coa(id, user_id, notes) do
      {:ok, coa} ->
        PubSub.broadcast(@pubsub, "ssa:coa", {:coa_approved, coa})
        {:reply, {:ok, serialize_coa(coa)}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "COA not found"}}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{reason: "Update failed", errors: format_errors(changeset)}}, socket}
    end
  end

  def handle_in("reject_coa", %{"id" => id, "user_id" => user_id, "notes" => notes}, socket) do
    case COA.reject_coa(id, user_id, notes) do
      {:ok, coa} ->
        PubSub.broadcast(@pubsub, "ssa:coa", {:coa_rejected, coa})
        {:reply, {:ok, serialize_coa(coa)}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "COA not found"}}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{reason: "Update failed", errors: format_errors(changeset)}}, socket}
    end
  end

  def handle_in("generate_coas", %{"conjunction_id" => conjunction_id}, socket) do
    case COAPlanner.generate_coas(conjunction_id) do
      {:ok, coas} ->
        PubSub.broadcast(@pubsub, "ssa:coa", {:coa_generated, coas})
        {:reply, {:ok, %{coas: Enum.map(coas, &serialize_coa/1)}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("get_satellite_conjunctions", %{"satellite_id" => satellite_id}, socket) do
    conjunctions = Conjunctions.list_conjunctions_for_satellite(satellite_id)
    {:reply, {:ok, %{conjunctions: Enum.map(conjunctions, &serialize_conjunction/1)}}, socket}
  end

  def handle_in("get_high_threat_objects", _payload, socket) do
    threats = SpaceObjects.list_high_threat_objects()
    {:reply, {:ok, %{objects: Enum.map(threats, &serialize_space_object/1)}}, socket}
  end

  # Serialization helpers

  defp serialize_conjunction(conjunction) do
    %{
      id: conjunction.id,
      primary_object_id: conjunction.primary_object_id,
      secondary_object_id: conjunction.secondary_object_id,
      tca: conjunction.tca,
      miss_distance_m: conjunction.miss_distance_m,
      miss_distance_radial_m: conjunction.miss_distance_radial_m,
      miss_distance_intrack_m: conjunction.miss_distance_intrack_m,
      miss_distance_crosstrack_m: conjunction.miss_distance_crosstrack_m,
      collision_probability: conjunction.collision_probability,
      relative_velocity_mps: conjunction.relative_velocity_mps,
      severity: conjunction.severity,
      status: conjunction.status,
      screening_id: conjunction.screening_id,
      data_source: conjunction.data_source,
      inserted_at: conjunction.inserted_at,
      updated_at: conjunction.updated_at
    }
  end

  defp serialize_coa(coa) do
    %{
      id: coa.id,
      conjunction_id: coa.conjunction_id,
      satellite_id: coa.satellite_id,
      coa_type: coa.coa_type,
      priority: coa.priority,
      status: coa.status,
      recommended: coa.recommended,
      title: coa.title,
      description: coa.description,
      delta_v_mps: coa.delta_v_mps,
      burn_duration_s: coa.burn_duration_s,
      maneuver_time: coa.maneuver_time,
      fuel_cost_kg: coa.fuel_cost_kg,
      post_maneuver_miss_m: coa.post_maneuver_miss_m,
      post_maneuver_pc: coa.post_maneuver_pc,
      effectiveness_score: coa.effectiveness_score,
      risk_score: coa.risk_score,
      mission_impact_score: coa.mission_impact_score,
      overall_score: coa.overall_score,
      decision_deadline: coa.decision_deadline,
      decision_time: coa.decision_time,
      decision_user: coa.decision_user,
      decision_notes: coa.decision_notes,
      execution_status: coa.execution_status,
      execution_start_time: coa.execution_start_time,
      execution_end_time: coa.execution_end_time,
      inserted_at: coa.inserted_at,
      updated_at: coa.updated_at
    }
  end

  defp serialize_space_object(object) do
    %{
      id: object.id,
      norad_id: object.norad_id,
      name: object.name,
      object_type: object.object_type,
      owner: object.owner,
      status: object.status,
      orbit_type: object.orbit_type,
      threat_level: object.threat_level,
      inclination_deg: object.inclination_deg,
      apogee_km: object.apogee_km,
      perigee_km: object.perigee_km,
      period_min: object.period_min,
      last_observed_at: object.last_observed_at,
      inserted_at: object.inserted_at,
      updated_at: object.updated_at
    }
  end

  defp serialize_detector_status(status) do
    %{
      running: status.running,
      last_screening: status.last_screening,
      next_screening: status.next_screening,
      conjunctions_found: status.conjunctions_found,
      objects_screened: status.objects_screened
    }
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp format_errors(error), do: error
end
