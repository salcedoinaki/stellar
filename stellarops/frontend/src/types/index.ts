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

// ============================================================================
// Conjunction & Threat Types (Phase 4)
// ============================================================================

export type ConjunctionSeverity = 'critical' | 'high' | 'medium' | 'low'
export type ConjunctionStatus = 'detected' | 'monitoring' | 'acknowledged' | 'resolved' | 'expired'

export interface Conjunction {
  id: string
  asset_id: string
  object_id: string
  tca: string  // ISO datetime
  miss_distance_km: number
  relative_velocity_km_s: number
  probability: number
  severity: ConjunctionSeverity
  status: ConjunctionStatus
  asset_position_at_tca?: Position
  object_position_at_tca?: Position
  covariance_data?: Record<string, unknown>
  acknowledged_at?: string
  acknowledged_by?: string
  inserted_at: string
  updated_at: string
  // Populated relations
  asset?: Satellite
  object?: SpaceObject
  threat_assessment?: ThreatAssessment
}

export type ObjectType = 'satellite' | 'debris' | 'rocket_body' | 'unknown'
export type OrbitalStatus = 'active' | 'decayed' | 'retired'

export interface SpaceObject {
  id: string
  norad_id: string
  name: string
  international_designator?: string
  object_type: ObjectType
  owner?: string
  country_code?: string
  launch_date?: string
  orbital_status: OrbitalStatus
  tle_line1?: string
  tle_line2?: string
  tle_epoch?: string
  apogee_km?: number
  perigee_km?: number
  inclination_deg?: number
  period_min?: number
  rcs_meters?: number
  inserted_at: string
  updated_at: string
}

export type ThreatClassification = 'hostile' | 'suspicious' | 'unknown' | 'friendly'
export type ThreatLevel = 'critical' | 'high' | 'medium' | 'low' | 'none'
export type ConfidenceLevel = 'high' | 'medium' | 'low'

export interface ThreatAssessment {
  id: string
  space_object_id: string
  classification: ThreatClassification
  capabilities: string[]
  threat_level: ThreatLevel
  intel_summary?: string
  notes?: string
  assessed_by?: string
  assessed_at: string
  confidence_level: ConfidenceLevel
}

// ============================================================================
// COA Types (Phase 4)
// ============================================================================

export type COAType = 'retrograde_burn' | 'prograde_burn' | 'inclination_change' | 'phasing' | 'flyby' | 'station_keeping'
export type COAStatus = 'proposed' | 'selected' | 'executing' | 'completed' | 'failed' | 'rejected'

export interface COA {
  id: string
  conjunction_id: string
  type: COAType
  name: string
  objective?: string
  description?: string
  delta_v_magnitude: number  // km/s
  delta_v_direction?: { x: number; y: number; z: number }
  burn_start_time?: string  // ISO datetime
  burn_duration_seconds?: number
  estimated_fuel_kg?: number
  predicted_miss_distance_km?: number
  risk_score: number  // 0-100
  status: COAStatus
  pre_burn_orbit?: OrbitalElements
  post_burn_orbit?: OrbitalElements
  selected_at?: string
  selected_by?: string
  executed_at?: string
  failure_reason?: string
  inserted_at: string
  updated_at: string
  // Populated relations
  conjunction?: Conjunction
  missions?: Mission[]
}

export interface OrbitalElements {
  a: number  // semi-major axis km
  e: number  // eccentricity
  i: number  // inclination degrees
  raan?: number
  argp?: number
  ta?: number
}

export interface COASimulationResult {
  coa_id: string
  coa_type: COAType
  original_miss_distance_km: number
  predicted_miss_distance_km: number
  miss_distance_improvement_km: number
  miss_distance_improvement_percent: number
  delta_v_magnitude: number
  fuel_consumption_kg?: number
  burn_duration_seconds?: number
  trajectory_points: TrajectoryPoint[]
  pre_burn_orbit?: OrbitalElements
  post_burn_orbit?: OrbitalElements
}

export interface TrajectoryPoint {
  timestamp: string
  position: Position
  altitude_km: number
}

// ============================================================================
// Mission Types (Phase 4)
// ============================================================================

export type MissionStatus = 'pending' | 'scheduled' | 'running' | 'completed' | 'failed' | 'canceled'
export type MissionPriority = 'critical' | 'high' | 'normal' | 'low'

export interface Mission {
  id: string
  name: string
  description?: string
  type: string
  satellite_id: string
  coa_id?: string
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

// ============================================================================
// Alarm Types (Phase 4)
// ============================================================================

export type AlarmSeverity = 'critical' | 'high' | 'medium' | 'low' | 'info'
export type AlarmStatus = 'active' | 'acknowledged' | 'resolved'

export interface Alarm {
  id: string
  satellite_id: string
  title: string
  message: string
  type: string
  severity: AlarmSeverity
  status: AlarmStatus
  acknowledged: boolean
  triggered_at: string
  acknowledged_at?: string
  acknowledged_by?: string
  resolved_at?: string
  resolution?: string
  data?: Record<string, unknown>
  inserted_at: string
  updated_at: string
}
