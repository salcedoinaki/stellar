//! gRPC service implementation

use std::sync::Arc;
use std::time::Instant;

use tokio::sync::RwLock;
use tonic::{Request, Response, Status};
use tracing::{debug, info, instrument, warn};

use crate::generated::orbital::{
    orbital_service_server::OrbitalService,
    EciPosition, EciVelocity, GeodeticPosition,
    HealthCheckRequest, HealthCheckResponse,
    Pass, PropagateRequest, PropagateResponse,
    TrajectoryPoint, TrajectoryRequest, TrajectoryResponse,
    VisibilityRequest, VisibilityResponse,
};
use crate::propagator;
use crate::AppState;

/// Implementation of the OrbitalService gRPC service
pub struct OrbitalServiceImpl {
    state: Arc<RwLock<AppState>>,
}

impl OrbitalServiceImpl {
    pub fn new(state: Arc<RwLock<AppState>>) -> Self {
        Self { state }
    }
}

#[tonic::async_trait]
impl OrbitalService for OrbitalServiceImpl {
    #[instrument(skip(self, request), fields(satellite_id))]
    async fn propagate_position(
        &self,
        request: Request<PropagateRequest>,
    ) -> Result<Response<PropagateResponse>, Status> {
        let start = Instant::now();
        let req = request.into_inner();

        let satellite_id = req.satellite_id.clone();
        tracing::Span::current().record("satellite_id", &satellite_id);

        debug!("PropagatePosition request for satellite {}", satellite_id);

        // Validate request
        let tle = req.tle.ok_or_else(|| Status::invalid_argument("TLE is required"))?;

        if tle.line1.is_empty() || tle.line2.is_empty() {
            return Err(Status::invalid_argument("TLE lines cannot be empty"));
        }

        // Propagate
        match propagator::propagate(&tle.line1, &tle.line2, req.timestamp_unix) {
            Ok(result) => {
                let elapsed = start.elapsed();
                
                // Update metrics
                {
                    let state = self.state.read().await;
                    state.metrics.record_propagation(elapsed, true);
                }

                info!(
                    satellite_id = %satellite_id,
                    elapsed_ms = %elapsed.as_millis(),
                    "Propagation successful"
                );

                Ok(Response::new(PropagateResponse {
                    satellite_id,
                    timestamp_unix: req.timestamp_unix,
                    position: Some(EciPosition {
                        x_km: result.position_km[0],
                        y_km: result.position_km[1],
                        z_km: result.position_km[2],
                    }),
                    velocity: Some(EciVelocity {
                        vx_km_s: result.velocity_km_s[0],
                        vy_km_s: result.velocity_km_s[1],
                        vz_km_s: result.velocity_km_s[2],
                    }),
                    geodetic: Some(GeodeticPosition {
                        latitude_deg: result.geodetic.latitude_deg,
                        longitude_deg: result.geodetic.longitude_deg,
                        altitude_km: result.geodetic.altitude_km,
                    }),
                    success: true,
                    error_message: String::new(),
                }))
            }
            Err(e) => {
                let elapsed = start.elapsed();
                
                // Update metrics
                {
                    let state = self.state.read().await;
                    state.metrics.record_propagation(elapsed, false);
                }

                warn!(
                    satellite_id = %satellite_id,
                    error = %e,
                    "Propagation failed"
                );

                Ok(Response::new(PropagateResponse {
                    satellite_id,
                    timestamp_unix: req.timestamp_unix,
                    position: None,
                    velocity: None,
                    geodetic: None,
                    success: false,
                    error_message: e.to_string(),
                }))
            }
        }
    }

    #[instrument(skip(self, request), fields(satellite_id, ground_station_id))]
    async fn calculate_visibility(
        &self,
        request: Request<VisibilityRequest>,
    ) -> Result<Response<VisibilityResponse>, Status> {
        let start = Instant::now();
        let req = request.into_inner();

        let satellite_id = req.satellite_id.clone();
        let ground_station = req.ground_station.ok_or_else(|| {
            Status::invalid_argument("Ground station is required")
        })?;
        let ground_station_id = ground_station.id.clone();

        tracing::Span::current().record("satellite_id", &satellite_id);
        tracing::Span::current().record("ground_station_id", &ground_station_id);

        debug!(
            "CalculateVisibility request for {} over {}",
            satellite_id, ground_station_id
        );

        // Validate request
        let _tle = req.tle.ok_or_else(|| Status::invalid_argument("TLE is required"))?;

        // For now, return a stub response
        // Full visibility calculation would require:
        // 1. Propagate satellite at intervals
        // 2. Calculate elevation from ground station
        // 3. Find AOS/LOS crossings of min elevation
        // 4. Calculate max elevation and azimuths

        let elapsed = start.elapsed();
        
        {
            let state = self.state.read().await;
            state.metrics.record_visibility(elapsed, true);
        }

        info!(
            satellite_id = %satellite_id,
            ground_station_id = %ground_station_id,
            elapsed_ms = %elapsed.as_millis(),
            "Visibility calculation complete (stub)"
        );

        // Return empty passes for now - full implementation would compute actual passes
        Ok(Response::new(VisibilityResponse {
            satellite_id,
            ground_station_id,
            passes: vec![
                // Example stub pass
                Pass {
                    aos_timestamp: req.start_timestamp_unix + 3600,
                    los_timestamp: req.start_timestamp_unix + 4200,
                    max_elevation_timestamp: req.start_timestamp_unix + 3900,
                    max_elevation_deg: 45.0,
                    aos_azimuth_deg: 270.0,
                    los_azimuth_deg: 90.0,
                    duration_seconds: 600,
                },
            ],
            success: true,
            error_message: String::new(),
        }))
    }

    #[instrument(skip(self, request), fields(satellite_id))]
    async fn propagate_trajectory(
        &self,
        request: Request<TrajectoryRequest>,
    ) -> Result<Response<TrajectoryResponse>, Status> {
        let start = Instant::now();
        let req = request.into_inner();

        let satellite_id = req.satellite_id.clone();
        tracing::Span::current().record("satellite_id", &satellite_id);

        debug!(
            "PropagateTrajectory request for {} from {} to {}",
            satellite_id, req.start_timestamp_unix, req.end_timestamp_unix
        );

        // Validate request
        let tle = req.tle.ok_or_else(|| Status::invalid_argument("TLE is required"))?;

        if req.step_seconds <= 0 {
            return Err(Status::invalid_argument("step_seconds must be positive"));
        }

        if req.end_timestamp_unix <= req.start_timestamp_unix {
            return Err(Status::invalid_argument(
                "end_timestamp must be after start_timestamp",
            ));
        }

        // Limit trajectory length to prevent DoS
        let max_points = 10000;
        let num_points = (req.end_timestamp_unix - req.start_timestamp_unix) / req.step_seconds + 1;
        if num_points > max_points {
            return Err(Status::invalid_argument(format!(
                "Trajectory would have {} points, max is {}",
                num_points, max_points
            )));
        }

        match propagator::propagate_trajectory(
            &tle.line1,
            &tle.line2,
            req.start_timestamp_unix,
            req.end_timestamp_unix,
            req.step_seconds,
        ) {
            Ok(results) => {
                let elapsed = start.elapsed();
                
                {
                    let state = self.state.read().await;
                    state.metrics.record_trajectory(elapsed, results.len(), true);
                }

                info!(
                    satellite_id = %satellite_id,
                    points = %results.len(),
                    elapsed_ms = %elapsed.as_millis(),
                    "Trajectory propagation successful"
                );

                let points: Vec<TrajectoryPoint> = results
                    .into_iter()
                    .map(|(ts, result)| TrajectoryPoint {
                        timestamp_unix: ts,
                        position: Some(EciPosition {
                            x_km: result.position_km[0],
                            y_km: result.position_km[1],
                            z_km: result.position_km[2],
                        }),
                        geodetic: Some(GeodeticPosition {
                            latitude_deg: result.geodetic.latitude_deg,
                            longitude_deg: result.geodetic.longitude_deg,
                            altitude_km: result.geodetic.altitude_km,
                        }),
                    })
                    .collect();

                Ok(Response::new(TrajectoryResponse {
                    satellite_id,
                    points,
                    success: true,
                    error_message: String::new(),
                }))
            }
            Err(e) => {
                let elapsed = start.elapsed();
                
                {
                    let state = self.state.read().await;
                    state.metrics.record_trajectory(elapsed, 0, false);
                }

                warn!(
                    satellite_id = %satellite_id,
                    error = %e,
                    "Trajectory propagation failed"
                );

                Ok(Response::new(TrajectoryResponse {
                    satellite_id,
                    points: vec![],
                    success: false,
                    error_message: e.to_string(),
                }))
            }
        }
    }

    async fn health_check(
        &self,
        _request: Request<HealthCheckRequest>,
    ) -> Result<Response<HealthCheckResponse>, Status> {
        let state = self.state.read().await;
        
        Ok(Response::new(HealthCheckResponse {
            healthy: true,
            version: env!("CARGO_PKG_VERSION").to_string(),
            uptime_seconds: state.start_time.elapsed().as_secs() as i64,
        }))
    }
}
