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
  name?: string
  description?: string
  type: string
  satellite_id: string | null
  ground_station_id?: string
  priority: MissionPriority
  status: MissionStatus
  deadline?: string | null
  scheduled_at?: string | null
  started_at?: string | null
  completed_at?: string | null
  energy_required?: number
  memory_required?: number
  required_energy?: number
  required_memory?: number
  required_bandwidth?: number
  estimated_duration?: number
  retry_count: number
  max_retries: number
  error_message?: string | null
  last_error?: string
  payload?: Record<string, unknown>
  result?: Record<string, unknown>
  inserted_at: string
  updated_at?: string
}

export type MissionType = 'imaging' | 'data_collection' | 'orbit_adjust' | 'downlink' | 'maintenance' | 'telemetry' | 'communication' | 'maneuver'
export type MissionPriority = 'critical' | 'high' | 'normal' | 'low'
export type MissionStatus = 'pending' | 'scheduled' | 'running' | 'completed' | 'failed' | 'cancelled' | 'canceled'

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

export type ContactWindowStatus = 'scheduled' | 'active' | 'completed' | 'missed'

// ============================================
// Space Situational Awareness (SSA) Types
// ============================================

// Space Object (tracked objects in orbit)
export interface SpaceObject {
  id: string
  norad_id: number
  name: string
  international_designator?: string
  object_type: SpaceObjectType
  owner?: string
  status: SpaceObjectStatus
  orbit_type: OrbitType
  orbital_parameters: OrbitalParameters
  tle: TLEData
  threat_assessment: ThreatAssessment
  physical_characteristics: PhysicalCharacteristics
  tracking: TrackingInfo
  is_protected_asset: boolean
  satellite_id?: string
  notes?: string
  inserted_at: string
  updated_at: string
}

export type SpaceObjectType = 'satellite' | 'debris' | 'rocket_body' | 'payload' | 'unknown'
export type SpaceObjectStatus = 'active' | 'inactive' | 'decayed' | 'unknown'
export type OrbitType = 'leo' | 'meo' | 'geo' | 'heo' | 'sso' | 'polar' | 'equatorial' | 'unknown'

export interface OrbitalParameters {
  inclination_deg?: number
  apogee_km?: number
  perigee_km?: number
  period_minutes?: number
  semi_major_axis_km?: number
  eccentricity?: number
  raan_deg?: number
  arg_perigee_deg?: number
  mean_anomaly_deg?: number
  mean_motion?: number
  bstar_drag?: number
}

export interface TLEData {
  line1?: string
  line2?: string
  epoch?: string
  updated_at?: string
}

export interface ThreatAssessment {
  threat_level: ThreatLevel
  classification: SecurityClassification
  capabilities: string[]
  intel_summary?: string
}

export type ThreatLevel = 'none' | 'low' | 'medium' | 'high' | 'critical'
export type SecurityClassification = 'unclassified' | 'confidential' | 'secret' | 'top_secret'

export interface PhysicalCharacteristics {
  radar_cross_section?: number
  size_class?: string
  launch_date?: string
  launch_site?: string
}

export interface TrackingInfo {
  last_observed_at?: string
  observation_count: number
  data_source?: string
}

// Conjunction (close approach event)
export interface Conjunction {
  id: string
  tca: string  // Time of Closest Approach
  tca_uncertainty_seconds: number
  miss_distance: MissDistance
  relative_velocity_ms?: number
  collision_probability?: number
  pc_method?: string
  severity: ConjunctionSeverity
  status: ConjunctionStatus
  primary_object?: SpaceObjectSummary
  secondary_object?: SpaceObjectSummary
  satellite_id?: string
  recommended_coa_id?: string
  executed_maneuver_id?: string
  data_source?: string
  cdm_id?: string
  screening_date?: string
  last_updated?: string
  notes?: string
  inserted_at: string
  updated_at: string
}

export interface MissDistance {
  total_m: number
  radial_m?: number
  in_track_m?: number
  cross_track_m?: number
  uncertainty_m?: number
}

export type ConjunctionSeverity = 'low' | 'medium' | 'high' | 'critical'
export type ConjunctionStatus = 'predicted' | 'active' | 'monitoring' | 'avoided' | 'passed' | 'maneuver_executed'

export interface SpaceObjectSummary {
  id: string
  norad_id: number
  name: string
  object_type: SpaceObjectType
  owner?: string
  threat_level: ThreatLevel
}

// Course of Action (COA)
export interface CourseOfAction {
  id: string
  coa_type: COAType
  priority: COAPriority
  status: COAStatus
  title: string
  description?: string
  rationale?: string
  conjunction_id?: string
  satellite_id: string
  maneuver: ManeuverParameters
  post_maneuver: PostManeuverPrediction
  scores: COAScores
  decision: DecisionInfo
  execution: ExecutionInfo
  risks: string[]
  assumptions: string[]
  alternative_coa_ids: string[]
  inserted_at: string
  updated_at: string
}

export type COAType = 'avoidance_maneuver' | 'monitor' | 'alert' | 'defensive_posture' | 'no_action'
export type COAPriority = 'low' | 'medium' | 'high' | 'critical'
export type COAStatus = 'proposed' | 'approved' | 'rejected' | 'executing' | 'completed' | 'failed' | 'superseded'

export interface ManeuverParameters {
  time?: string
  delta_v_ms?: number
  delta_v_radial_ms?: number
  delta_v_in_track_ms?: number
  delta_v_cross_track_ms?: number
  burn_duration_s?: number
  fuel_cost_kg?: number
}

export interface PostManeuverPrediction {
  miss_distance_m?: number
  collision_probability?: number
  new_orbit_apogee_km?: number
  new_orbit_perigee_km?: number
}

export interface COAScores {
  risk_if_no_action?: number
  effectiveness?: number
  mission_impact?: number
  overall?: number
}

export interface DecisionInfo {
  deadline?: string
  decided_by?: string
  decided_at?: string
  notes?: string
}

export interface ExecutionInfo {
  command_id?: string
  started_at?: string
  completed_at?: string
  result?: Record<string, unknown>
}

// SSA Statistics
export interface ConjunctionStatistics {
  total_upcoming: number
  critical_next_24h: number
  critical_next_7d: number
  maneuvers_pending: number
  by_severity: Record<ConjunctionSeverity, number>
  by_status: Record<ConjunctionStatus, number>
}

export interface SpaceObjectCounts {
  by_type: Record<SpaceObjectType, number>
  by_threat: Record<ThreatLevel, number>
}

// SSA Detector Status
export interface DetectorStatus {
  screening_interval_ms: number
  prediction_window_hours: number
  miss_distance_threshold_m: number
  last_screening_at?: string
  conjunctions_found: number
  screening_in_progress: boolean
}

// Visibility Pass (for ground contact)
export interface VisibilityPass {
  aos_time: string
  los_time: string
  tca_time: string
  max_elevation_deg: number
  aos_azimuth_deg: number
  los_azimuth_deg: number
  duration_seconds: number
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
