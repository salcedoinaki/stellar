// Satellite types
export interface Satellite {
  id: string
  name?: string
  mode: SatelliteMode
  energy: number
  memory: number
  latitude?: number
  longitude?: number
  altitude?: number
  status?: 'online' | 'offline' | 'warning'
  tle_line1?: string
  tle_line2?: string
  inserted_at?: string
  updated_at?: string
}

// Mode must match backend: :nominal | :safe | :survival
export type SatelliteMode = 'nominal' | 'safe' | 'survival'

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
  code: string
  latitude: number
  longitude: number
  altitude_m?: number
  elevation_mask: number
  status: GroundStationStatus
  bandwidth_mbps?: number
}

export type GroundStationStatus = 'online' | 'offline' | 'maintenance'

// Mission types
export interface Mission {
  id: string
  name: string
  description?: string
  type: MissionType
  satellite_id: string
  ground_station_id?: string
  priority: MissionPriority
  status: MissionStatus
  deadline?: string
  scheduled_at?: string
  started_at?: string
  completed_at?: string
  required_energy: number
  required_memory: number
  required_bandwidth: number
  estimated_duration: number
  retry_count: number
  max_retries: number
  last_error?: string
  payload?: Record<string, unknown>
  result?: Record<string, unknown>
  inserted_at: string
  updated_at: string
}

export type MissionType = 'imaging' | 'data_collection' | 'orbit_adjust' | 'downlink' | 'maintenance'
export type MissionPriority = 'critical' | 'high' | 'normal' | 'low'
export type MissionStatus = 'pending' | 'scheduled' | 'running' | 'completed' | 'failed' | 'canceled'

// Alarm types
export interface Alarm {
  id: string
  type: string
  severity: AlarmSeverity
  message: string
  source: string
  details?: Record<string, unknown>
  status: AlarmStatus
  satellite_id?: string
  mission_id?: string
  acknowledged_at?: string
  acknowledged_by?: string
  resolved_at?: string
  inserted_at: string
}

export type AlarmSeverity = 'critical' | 'major' | 'minor' | 'warning' | 'info'
export type AlarmStatus = 'active' | 'acknowledged' | 'resolved'

// Contact window types
export interface ContactWindow {
  id: string
  satellite_id: string
  ground_station_id: string
  ground_station?: GroundStation
  aos_time: string
  los_time: string
  max_elevation_time: string
  max_elevation_deg: number
  aos_azimuth_deg: number
  los_azimuth_deg: number
  duration_seconds: number
  status: ContactWindowStatus
}
