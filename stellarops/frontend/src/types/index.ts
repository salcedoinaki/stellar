// Satellite types
export interface Satellite {
  id: string
  mode: SatelliteMode
  energy: number
  memory: number
  latitude?: number
  longitude?: number
  altitude?: number
  status?: 'online' | 'offline' | 'warning'
  inserted_at?: string
  updated_at?: string
}

export type SatelliteMode = 'nominal' | 'safe' | 'critical' | 'standby'

export interface SatelliteState {
  id: string
  mode: SatelliteMode
  energy: number
  memory: number
  pending_tasks: number
}

// Telemetry types
export interface TelemetryEvent {
  id?: string
  satellite_id: string
  event_type: string
  payload: Record<string, unknown>
  recorded_at: string
}

export interface TelemetryData {
  timestamp: number
  energy: number
  memory: number
  temperature?: number
}

// Command types
export interface Command {
  id: string
  satellite_id: string
  command_type: string
  parameters: Record<string, unknown>
  status: CommandStatus
  scheduled_at?: string
  executed_at?: string
  inserted_at: string
}

export type CommandStatus = 'pending' | 'executing' | 'completed' | 'failed' | 'cancelled'

// API response types
export interface ApiResponse<T> {
  data: T
}

export interface ApiError {
  error: string
  message?: string
}

// Position types (from orbital service)
export interface Position {
  x_km: number
  y_km: number
  z_km: number
}

export interface Velocity {
  vx_km_s: number
  vy_km_s: number
  vz_km_s: number
}

export interface GeodeticCoords {
  latitude_deg: number
  longitude_deg: number
  altitude_km: number
}

export interface PropagationResult {
  satellite_id: string
  timestamp_unix: number
  position: Position
  velocity: Velocity
  geodetic: GeodeticCoords
  success: boolean
  error?: string
}

// WebSocket payload types
export interface SatelliteUpdatedPayload {
  satellite_id: string
  mode?: SatelliteMode
  energy?: number
  memory?: number
}

export interface TelemetryEventPayload {
  satellite_id: string
  event_type: string
  payload: Record<string, unknown>
  recorded_at: string
}

export interface ModeChangedPayload {
  satellite_id: string
  old_mode: SatelliteMode
  new_mode: SatelliteMode
}

// Chart data types
export interface ChartDataPoint {
  time: string
  value: number
  label?: string
}

// Ground station types
export interface GroundStation {
  id: string
  name: string
  latitude: number
  longitude: number
  elevation_mask: number
}
