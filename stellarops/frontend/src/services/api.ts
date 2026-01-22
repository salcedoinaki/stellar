import type { 
  Satellite, 
  TelemetryEvent, 
  Command, 
  ApiResponse, 
  PropagationResult,
  Conjunction,
  SpaceObject,
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
// Conjunctions API (Phase 4)
// ============================================================================

export interface ConjunctionFilters {
  asset_id?: string
  severity?: string
  status?: string
  tca_after?: string
  tca_before?: string
  page?: number
  per_page?: number
}

export async function fetchConjunctions(filters?: ConjunctionFilters): Promise<Conjunction[]> {
  const params = new URLSearchParams()
  if (filters) {
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined) params.append(key, String(value))
    })
  }
  const url = `${API_BASE}/api/conjunctions${params.toString() ? `?${params}` : ''}`
  const response = await fetch(url)
  const data = await handleResponse<ApiResponse<Conjunction[]>>(response)
  return data.data
}

export async function fetchConjunction(id: string): Promise<Conjunction> {
  const response = await fetch(`${API_BASE}/api/conjunctions/${id}`)
  const data = await handleResponse<ApiResponse<Conjunction>>(response)
  return data.data
}

export async function acknowledgeConjunction(id: string): Promise<Conjunction> {
  const response = await fetch(`${API_BASE}/api/conjunctions/${id}/acknowledge`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  })
  const data = await handleResponse<ApiResponse<Conjunction>>(response)
  return data.data
}

export async function resolveConjunction(id: string): Promise<Conjunction> {
  const response = await fetch(`${API_BASE}/api/conjunctions/${id}/resolve`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  })
  const data = await handleResponse<ApiResponse<Conjunction>>(response)
  return data.data
}

// ============================================================================
// Space Objects API (Phase 4)
// ============================================================================

export async function fetchSpaceObjects(): Promise<SpaceObject[]> {
  const response = await fetch(`${API_BASE}/api/objects`)
  const data = await handleResponse<ApiResponse<SpaceObject[]>>(response)
  return data.data
}

export async function fetchSpaceObject(noradId: string): Promise<SpaceObject> {
  const response = await fetch(`${API_BASE}/api/objects/${noradId}`)
  const data = await handleResponse<ApiResponse<SpaceObject>>(response)
  return data.data
}

// ============================================================================
// COA API (Phase 4)
// ============================================================================

export async function fetchCOAsForConjunction(conjunctionId: string): Promise<COA[]> {
  const response = await fetch(`${API_BASE}/api/conjunctions/${conjunctionId}/coas`)
  const data = await handleResponse<ApiResponse<COA[]>>(response)
  return data.data
}

export async function fetchCOA(id: string): Promise<COA> {
  const response = await fetch(`${API_BASE}/api/coas/${id}`)
  const data = await handleResponse<ApiResponse<COA>>(response)
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
// Mission API (Phase 4)
// ============================================================================

export interface MissionFilters {
  satellite_id?: string
  status?: string
  priority?: string
  page?: number
  per_page?: number
}

export async function fetchMissions(filters?: MissionFilters): Promise<Mission[]> {
  const params = new URLSearchParams()
  if (filters) {
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined) params.append(key, String(value))
    })
  }
  const url = `${API_BASE}/api/missions${params.toString() ? `?${params}` : ''}`
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
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
  })
  const data = await handleResponse<ApiResponse<Mission>>(response)
  return data.data
}

// ============================================================================
// Alarms API (Phase 4)
// ============================================================================

export interface AlarmFilters {
  severity?: string
  status?: string
  source_type?: string
  page?: number
  per_page?: number
}

export async function fetchAlarms(filters?: AlarmFilters): Promise<Alarm[]> {
  const params = new URLSearchParams()
  if (filters) {
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined) params.append(key, String(value))
    })
  }
  const url = `${API_BASE}/api/alarms${params.toString() ? `?${params}` : ''}`
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

export async function resolveAlarm(id: string): Promise<Alarm> {
  const response = await fetch(`${API_BASE}/api/alarms/${id}/resolve`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
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
  conjunctions: {
    list: fetchConjunctions,
    get: fetchConjunction,
    acknowledge: acknowledgeConjunction,
    resolve: resolveConjunction,
  },
  spaceObjects: {
    list: fetchSpaceObjects,
    get: fetchSpaceObject,
  },
  coas: {
    listForConjunction: fetchCOAsForConjunction,
    get: fetchCOA,
    select: selectCOA,
    simulate: simulateCOA,
    regenerate: regenerateCOAs,
  },
  missions: {
    list: fetchMissions,
    get: fetchMission,
    create: createMission,
    cancel: cancelMission,
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
