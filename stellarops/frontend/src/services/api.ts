import type { 
  Satellite, 
  TelemetryEvent, 
  Command, 
  ApiResponse, 
  PropagationResult,
  SpaceObject,
  Conjunction,
  CourseOfAction,
  ConjunctionStatistics,
  DetectorStatus,
  COA,
  COASimulationResult,
  Mission,
  Alarm
} from '../types'

const API_BASE = import.meta.env.VITE_API_URL || ''

async function handleResponse<T>(response: Response): Promise<T> {
  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Unknown error' }))
    throw new Error(error.message || error.error || `HTTP ${response.status}`)
  }
  return response.json()
}

// ============================================================================
// Satellites API
// ============================================================================

export async function fetchSatellites(): Promise<Satellite[]> {
  const response = await fetch(`${API_BASE}/api/satellites`)
  const data = await handleResponse<ApiResponse<Satellite[]>>(response)
  return data.data
}

export async function fetchSatellite(id: string): Promise<Satellite> {
  const response = await fetch(`${API_BASE}/api/satellites/${id}`)
  const data = await handleResponse<ApiResponse<Satellite>>(response)
  return data.data
}

export async function createSatellite(satellite: Partial<Satellite>): Promise<Satellite> {
  const response = await fetch(`${API_BASE}/api/satellites`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ satellite }),
  })
  const data = await handleResponse<ApiResponse<Satellite>>(response)
  return data.data
}

export async function updateSatellite(id: string, updates: Partial<Satellite>): Promise<Satellite> {
  const response = await fetch(`${API_BASE}/api/satellites/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ satellite: updates }),
  })
  const data = await handleResponse<ApiResponse<Satellite>>(response)
  return data.data
}

export async function deleteSatellite(id: string): Promise<void> {
  const response = await fetch(`${API_BASE}/api/satellites/${id}`, {
    method: 'DELETE',
  })
  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Unknown error' }))
    throw new Error(error.message || error.error || `HTTP ${response.status}`)
  }
}

// ============================================================================
// Satellite State API (from GenServer)
// ============================================================================

export async function fetchSatelliteState(id: string): Promise<Satellite> {
  const response = await fetch(`${API_BASE}/api/satellites/${id}/state`)
  const data = await handleResponse<ApiResponse<Satellite>>(response)
  return data.data
}

export async function updateSatelliteMode(id: string, mode: string): Promise<Satellite> {
  const response = await fetch(`${API_BASE}/api/satellites/${id}/mode`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ mode }),
  })
  const data = await handleResponse<ApiResponse<Satellite>>(response)
  return data.data
}

// ============================================================================
// Telemetry API
// ============================================================================

export async function fetchTelemetry(satelliteId: string): Promise<TelemetryEvent[]> {
  const response = await fetch(`${API_BASE}/api/satellites/${satelliteId}/telemetry`)
  const data = await handleResponse<ApiResponse<TelemetryEvent[]>>(response)
  return data.data
}

export async function createTelemetryEvent(satelliteId: string, event: Partial<TelemetryEvent>): Promise<TelemetryEvent> {
  const response = await fetch(`${API_BASE}/api/satellites/${satelliteId}/telemetry`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ telemetry_event: event }),
  })
  const data = await handleResponse<ApiResponse<TelemetryEvent>>(response)
  return data.data
}

// ============================================================================
// Commands API
// ============================================================================

export async function fetchCommands(satelliteId: string): Promise<Command[]> {
  const response = await fetch(`${API_BASE}/api/satellites/${satelliteId}/commands`)
  const data = await handleResponse<ApiResponse<Command[]>>(response)
  return data.data
}

export async function createCommand(satelliteId: string, command: Partial<Command>): Promise<Command> {
  const response = await fetch(`${API_BASE}/api/satellites/${satelliteId}/commands`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ command }),
  })
  const data = await handleResponse<ApiResponse<Command>>(response)
  return data.data
}

// ============================================================================
// Orbital API (via Rust service)
// ============================================================================

const ORBITAL_BASE = import.meta.env.VITE_ORBITAL_URL || 'http://localhost:9090'

export async function propagatePosition(
  satelliteId: string,
  tleLine1: string,
  tleLine2: string,
  timestampUnix: number
): Promise<PropagationResult> {
  const response = await fetch(`${ORBITAL_BASE}/api/propagate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      satellite_id: satelliteId,
      tle_line1: tleLine1,
      tle_line2: tleLine2,
      timestamp_unix: timestampUnix,
    }),
  })
  return handleResponse<PropagationResult>(response)
}

export async function checkOrbitalHealth(): Promise<{ status: string; uptime_seconds: number }> {
  const response = await fetch(`${ORBITAL_BASE}/health`)
  return handleResponse(response)
}

// ============================================================================
// Space Objects API (SSA)
// ============================================================================

// Transform space object to ensure threat_assessment exists
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function transformSpaceObject(raw: any): SpaceObject {
  return {
    ...raw,
    threat_assessment: raw.threat_assessment ?? {
      threat_level: 'none',
      is_active_threat: false,
    },
  }
}

export interface SpaceObjectFilters {
  object_type?: string
  threat_level?: string
  owner?: string
  orbit_type?: string
  status?: string
  limit?: number
  offset?: number
}

export async function fetchSpaceObjects(filters?: SpaceObjectFilters): Promise<SpaceObject[]> {
  const params = new URLSearchParams()
  if (filters) {
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        params.append(key, String(value))
      }
    })
  }
  const queryString = params.toString()
  const url = `${API_BASE}/api/space_objects${queryString ? `?${queryString}` : ''}`
  const response = await fetch(url)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any[]>>(response)
  return (data.data || []).map(transformSpaceObject)
}

export async function fetchSpaceObject(id: string): Promise<SpaceObject> {
  const response = await fetch(`${API_BASE}/api/space_objects/${id}`)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any>>(response)
  return transformSpaceObject(data.data)
}

export async function fetchSpaceObjectByNorad(noradId: number): Promise<SpaceObject> {
  const response = await fetch(`${API_BASE}/api/space_objects/norad/${noradId}`)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any>>(response)
  return transformSpaceObject(data.data)
}

export async function fetchHighThreatObjects(): Promise<SpaceObject[]> {
  const response = await fetch(`${API_BASE}/api/space_objects/high_threat`)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any[]>>(response)
  return (data.data || []).map(transformSpaceObject)
}

export async function fetchProtectedAssets(): Promise<SpaceObject[]> {
  const response = await fetch(`${API_BASE}/api/space_objects/protected_assets`)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any[]>>(response)
  return (data.data || []).map(transformSpaceObject)
}

export async function fetchDebrisObjects(): Promise<SpaceObject[]> {
  const response = await fetch(`${API_BASE}/api/space_objects/debris`)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any[]>>(response)
  return (data.data || []).map(transformSpaceObject)
}

export async function searchSpaceObjects(query: string): Promise<SpaceObject[]> {
  const response = await fetch(`${API_BASE}/api/space_objects/search?q=${encodeURIComponent(query)}`)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any[]>>(response)
  return (data.data || []).map(transformSpaceObject)
}

export async function updateThreatAssessment(
  id: string, 
  assessment: { threat_level?: string; intel_summary?: string; capabilities?: string[] }
): Promise<SpaceObject> {
  const response = await fetch(`${API_BASE}/api/space_objects/${id}/threat`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(assessment),
  })
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any>>(response)
  return transformSpaceObject(data.data)
}

// ============================================================================
// Conjunctions API
// ============================================================================

// Transform backend conjunction response to frontend format
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function transformConjunction(raw: any): Conjunction {
  // Convert backend field names to frontend expected names
  const missDistanceM = raw.miss_distance_m ?? 0
  const missDistanceKm = missDistanceM / 1000

  // Build object with rcs_meters from secondary_object
  const secondaryObject = raw.secondary_object
    ? {
        ...raw.secondary_object,
        rcs_meters: raw.secondary_object.rcs_meters ?? 0.1, // Default if not provided
      }
    : undefined

  return {
    ...raw,
    // Map new field names to legacy field names expected by UI
    miss_distance_km: missDistanceKm,
    miss_distance: {
      total_m: missDistanceM,
      radial_m: raw.miss_distance_radial_m ?? 0,
      in_track_m: raw.miss_distance_in_track_m ?? 0,
      cross_track_m: raw.miss_distance_cross_track_m ?? 0,
      uncertainty_m: raw.miss_distance_uncertainty_m ?? 0,
    },
    relative_velocity_km_s: (raw.relative_velocity_ms ?? 0) / 1000,
    probability: raw.collision_probability ?? 0,
    // Map object references
    object: secondaryObject,
    object_id: raw.secondary_object_id,
    asset_id: raw.satellite_id ?? raw.primary_object_id,
    asset: raw.primary_object
      ? {
          id: raw.primary_object.id,
          name: raw.primary_object.name,
        }
      : undefined,
    // Position data at TCA (mock if not provided by backend)
    asset_position_at_tca: raw.asset_position_at_tca ?? {
      x_km: 0,
      y_km: 0,
      z_km: 0,
    },
    object_position_at_tca: raw.object_position_at_tca ?? {
      x_km: 0,
      y_km: 0,
      z_km: 0,
    },
  }
}

export interface ConjunctionFilters {
  satellite_id?: string
  asset_id?: string
  severity?: string
  status?: string
  from?: string
  to?: string
  tca_after?: string
  tca_before?: string
  limit?: number
  upcoming?: boolean
  page?: number
  per_page?: number
}

export async function fetchConjunctions(filters?: ConjunctionFilters): Promise<Conjunction[]> {
  const params = new URLSearchParams()
  if (filters) {
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        params.append(key, String(value))
      }
    })
  }
  const queryString = params.toString()
  const url = `${API_BASE}/api/conjunctions${queryString ? `?${queryString}` : ''}`
  const response = await fetch(url)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any[]>>(response)
  return (data.data || []).map(transformConjunction)
}

export async function fetchCriticalConjunctions(): Promise<Conjunction[]> {
  const response = await fetch(`${API_BASE}/api/conjunctions/critical`)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any[]>>(response)
  return (data.data || []).map(transformConjunction)
}

export async function fetchConjunction(id: string): Promise<Conjunction> {
  const response = await fetch(`${API_BASE}/api/conjunctions/${id}`)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any>>(response)
  return transformConjunction(data.data)
}

export async function acknowledgeConjunction(id: string): Promise<Conjunction> {
  const response = await fetch(`${API_BASE}/api/conjunctions/${id}/acknowledge`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  })
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any>>(response)
  return transformConjunction(data.data)
}

export async function resolveConjunction(id: string): Promise<Conjunction> {
  const response = await fetch(`${API_BASE}/api/conjunctions/${id}/resolve`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  })
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any>>(response)
  return transformConjunction(data.data)
}

export async function fetchConjunctionStatistics(): Promise<ConjunctionStatistics> {
  const response = await fetch(`${API_BASE}/api/conjunctions/statistics`)
  const data = await handleResponse<{ data: ConjunctionStatistics }>(response)
  return data.data
}

export async function fetchDetectorStatus(): Promise<DetectorStatus> {
  const response = await fetch(`${API_BASE}/api/conjunctions/detector_status`)
  const data = await handleResponse<{ data: DetectorStatus }>(response)
  return data.data
}

export async function triggerScreening(): Promise<{ status: string; message: string }> {
  const response = await fetch(`${API_BASE}/api/conjunctions/trigger_screening`, {
    method: 'POST',
  })
  return handleResponse(response)
}

export async function fetchConjunctionsForSatellite(satelliteId: string): Promise<Conjunction[]> {
  const response = await fetch(`${API_BASE}/api/conjunctions/satellite/${satelliteId}`)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = await handleResponse<ApiResponse<any[]>>(response)
  return (data.data || []).map(transformConjunction)
}

// ============================================================================
// Course of Action (COA) API
// ============================================================================

export async function fetchCOAs(filters?: { satellite_id?: string; status?: string; limit?: number }): Promise<CourseOfAction[]> {
  const params = new URLSearchParams()
  if (filters) {
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        params.append(key, String(value))
      }
    })
  }
  const queryString = params.toString()
  const url = `${API_BASE}/api/coas${queryString ? `?${queryString}` : ''}`
  const response = await fetch(url)
  const data = await handleResponse<ApiResponse<CourseOfAction[]>>(response)
  return data.data
}

export async function fetchPendingCOAs(): Promise<CourseOfAction[]> {
  const response = await fetch(`${API_BASE}/api/coas/pending`)
  const data = await handleResponse<ApiResponse<CourseOfAction[]>>(response)
  return data.data
}

export async function fetchUrgentCOAs(hours?: number): Promise<CourseOfAction[]> {
  const url = hours 
    ? `${API_BASE}/api/coas/urgent?hours=${hours}`
    : `${API_BASE}/api/coas/urgent`
  const response = await fetch(url)
  const data = await handleResponse<ApiResponse<CourseOfAction[]>>(response)
  return data.data
}

export async function fetchCOA(id: string): Promise<CourseOfAction | COA> {
  const response = await fetch(`${API_BASE}/api/coas/${id}`)
  const data = await handleResponse<ApiResponse<CourseOfAction | COA>>(response)
  return data.data
}

export async function fetchCOAsForConjunction(conjunctionId: string): Promise<CourseOfAction[] | COA[]> {
  const response = await fetch(`${API_BASE}/api/coas/conjunction/${conjunctionId}`)
  const data = await handleResponse<ApiResponse<CourseOfAction[] | COA[]>>(response)
  return data.data
}

export async function fetchRecommendedCOA(conjunctionId: string): Promise<CourseOfAction> {
  const response = await fetch(`${API_BASE}/api/coas/conjunction/${conjunctionId}/recommended`)
  const data = await handleResponse<ApiResponse<CourseOfAction>>(response)
  return data.data
}

export async function approveCOA(id: string, approvedBy: string, notes?: string): Promise<CourseOfAction> {
  const response = await fetch(`${API_BASE}/api/coas/${id}/approve`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ approved_by: approvedBy, notes }),
  })
  const data = await handleResponse<ApiResponse<CourseOfAction>>(response)
  return data.data
}

export async function rejectCOA(id: string, rejectedBy: string, notes?: string): Promise<CourseOfAction> {
  const response = await fetch(`${API_BASE}/api/coas/${id}/reject`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ rejected_by: rejectedBy, notes }),
  })
  const data = await handleResponse<ApiResponse<CourseOfAction>>(response)
  return data.data
}

export async function generateCOAs(conjunctionId: string): Promise<CourseOfAction[]> {
  const response = await fetch(`${API_BASE}/api/coas/conjunction/${conjunctionId}/generate`, {
    method: 'POST',
  })
  const data = await handleResponse<ApiResponse<CourseOfAction[]>>(response)
  return data.data
}

export async function selectCOA(id: string, selectedBy?: string): Promise<{ data: COA; missions: Mission[] }> {
  const response = await fetch(`${API_BASE}/api/coas/${id}/select`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ selected_by: selectedBy }),
  })
  return handleResponse(response)
}

export async function simulateCOA(id: string): Promise<COASimulationResult> {
  const response = await fetch(`${API_BASE}/api/coas/${id}/simulate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  })
  const data = await handleResponse<ApiResponse<COASimulationResult>>(response)
  return data.data
}

export async function regenerateCOAs(conjunctionId: string): Promise<COA[]> {
  const response = await fetch(`${API_BASE}/api/conjunctions/${conjunctionId}/coas/regenerate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  })
  const data = await handleResponse<ApiResponse<COA[]>>(response)
  return data.data
}

// ============================================================================
// Missions API
// ============================================================================

export interface MissionFilters {
  satellite_id?: string
  status?: string
  priority?: string
  limit?: number
  page?: number
  per_page?: number
}

export async function fetchMissions(filters?: MissionFilters): Promise<Mission[]> {
  const params = new URLSearchParams()
  if (filters) {
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        params.append(key, String(value))
      }
    })
  }
  const queryString = params.toString()
  const url = `${API_BASE}/api/missions${queryString ? `?${queryString}` : ''}`
  const response = await fetch(url)
  const data = await handleResponse<ApiResponse<Mission[]>>(response)
  return data.data
}

export async function fetchMission(id: string): Promise<Mission> {
  const response = await fetch(`${API_BASE}/api/missions/${id}`)
  const data = await handleResponse<ApiResponse<Mission>>(response)
  return data.data
}

export async function createMission(mission: Partial<Mission>): Promise<Mission> {
  const response = await fetch(`${API_BASE}/api/missions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ mission }),
  })
  const data = await handleResponse<ApiResponse<Mission>>(response)
  return data.data
}

export async function cancelMission(id: string): Promise<Mission> {
  const response = await fetch(`${API_BASE}/api/missions/${id}/cancel`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  })
  const data = await handleResponse<ApiResponse<Mission>>(response)
  return data.data
}

export async function retryMission(id: string): Promise<Mission> {
  const response = await fetch(`${API_BASE}/api/missions/${id}/retry`, {
    method: 'POST',
  })
  const data = await handleResponse<ApiResponse<Mission>>(response)
  return data.data
}

// ============================================================================
// Alarms API
// ============================================================================

export interface AlarmFilters {
  severity?: string
  status?: string
  source?: string
  source_type?: string
  satellite_id?: string
  limit?: number
  page?: number
  per_page?: number
}

export async function fetchAlarms(filters?: AlarmFilters): Promise<Alarm[]> {
  const params = new URLSearchParams()
  if (filters) {
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        params.append(key, String(value))
      }
    })
  }
  const queryString = params.toString()
  const url = `${API_BASE}/api/alarms${queryString ? `?${queryString}` : ''}`
  const response = await fetch(url)
  const data = await handleResponse<ApiResponse<Alarm[]>>(response)
  return data.data
}

export async function fetchAlarm(id: string): Promise<Alarm> {
  const response = await fetch(`${API_BASE}/api/alarms/${id}`)
  const data = await handleResponse<ApiResponse<Alarm>>(response)
  return data.data
}

export async function acknowledgeAlarm(id: string): Promise<Alarm> {
  const response = await fetch(`${API_BASE}/api/alarms/${id}/acknowledge`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  })
  const data = await handleResponse<ApiResponse<Alarm>>(response)
  return data.data
}

export async function resolveAlarm(id: string, resolution?: string): Promise<Alarm> {
  const response = await fetch(`${API_BASE}/api/alarms/${id}/resolve`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ resolution }),
  })
  const data = await handleResponse<ApiResponse<Alarm>>(response)
  return data.data
}

export async function fetchAlarmsSummary(): Promise<Record<string, number>> {
  const response = await fetch(`${API_BASE}/api/alarms/summary`)
  const data = await handleResponse<ApiResponse<Record<string, number>>>(response)
  return data.data
}

// ============================================================================
// API Client Object
// ============================================================================

export const api = {
  satellites: {
    list: fetchSatellites,
    get: fetchSatellite,
    create: createSatellite,
    update: updateSatellite,
    delete: deleteSatellite,
    getState: fetchSatelliteState,
    updateMode: updateSatelliteMode,
  },
  telemetry: {
    list: fetchTelemetry,
    create: createTelemetryEvent,
  },
  commands: {
    list: fetchCommands,
    create: createCommand,
  },
  orbital: {
    propagate: propagatePosition,
    health: checkOrbitalHealth,
  },
  spaceObjects: {
    list: fetchSpaceObjects,
    get: fetchSpaceObject,
    getByNorad: fetchSpaceObjectByNorad,
    highThreat: fetchHighThreatObjects,
    protectedAssets: fetchProtectedAssets,
    debris: fetchDebrisObjects,
    search: searchSpaceObjects,
    updateThreat: updateThreatAssessment,
  },
  conjunctions: {
    list: fetchConjunctions,
    get: fetchConjunction,
    critical: fetchCriticalConjunctions,
    forSatellite: fetchConjunctionsForSatellite,
    statistics: fetchConjunctionStatistics,
    detectorStatus: fetchDetectorStatus,
    triggerScreening: triggerScreening,
    acknowledge: acknowledgeConjunction,
    resolve: resolveConjunction,
  },
  coas: {
    list: fetchCOAs,
    get: fetchCOA,
    pending: fetchPendingCOAs,
    urgent: fetchUrgentCOAs,
    forConjunction: fetchCOAsForConjunction,
    recommended: fetchRecommendedCOA,
    approve: approveCOA,
    reject: rejectCOA,
    generate: generateCOAs,
    select: selectCOA,
    simulate: simulateCOA,
    regenerate: regenerateCOAs,
  },
  missions: {
    list: fetchMissions,
    get: fetchMission,
    create: createMission,
    cancel: cancelMission,
    retry: retryMission,
  },
  alarms: {
    list: fetchAlarms,
    get: fetchAlarm,
    acknowledge: acknowledgeAlarm,
    resolve: resolveAlarm,
    summary: fetchAlarmsSummary,
  },
}

export default api
