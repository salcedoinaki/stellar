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
}

export default api
