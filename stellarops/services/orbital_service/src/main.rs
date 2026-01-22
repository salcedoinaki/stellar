//! Orbital propagation service using SGP4
//!
//! This service provides gRPC endpoints for satellite position calculation
//! using Two-Line Element (TLE) sets and the SGP4 propagation algorithm.
//!
//! Additionally, HTTP/JSON endpoints are provided for easy integration.

mod generated;
mod metrics;
mod propagator;
mod service;

#[cfg(test)]
mod tests;

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;

use axum::{
    extract::State,
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
use tonic::transport::Server;
use tracing::{info, Level};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

use crate::generated::orbital::orbital_service_server::OrbitalServiceServer;
use crate::metrics::MetricsState;
use crate::service::OrbitalServiceImpl;

/// Application state shared across services
pub struct AppState {
    pub start_time: Instant,
    pub metrics: MetricsState,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            start_time: Instant::now(),
            metrics: MetricsState::new(),
        }
    }

    pub fn uptime_seconds(&self) -> u64 {
        self.start_time.elapsed().as_secs()
    }
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// HTTP/JSON API types
// ============================================================================

#[derive(Debug, Deserialize)]
struct PropagateRequest {
    satellite_id: String,
    tle_line1: String,
    tle_line2: String,
    timestamp_unix: i64,
}

// TASK-157: Batch propagation request
#[derive(Debug, Deserialize)]
struct BatchPropagateRequest {
    requests: Vec<PropagateRequest>,
}

// TASK-158: Trajectory request for time range propagation
#[derive(Debug, Deserialize)]
struct TrajectoryRequest {
    satellite_id: String,
    tle_line1: String,
    tle_line2: String,
    start_unix: i64,
    end_unix: i64,
    #[serde(default = "default_step")]
    step_seconds: i64,
}

fn default_step() -> i64 {
    60  // Default 1 minute intervals
}

// TASK-159: Visibility calculation request
#[derive(Debug, Deserialize)]
struct VisibilityRequest {
    satellite_id: String,
    tle_line1: String,
    tle_line2: String,
    ground_station: GroundStation,
    start_unix: i64,
    end_unix: i64,
}

#[derive(Debug, Deserialize)]
struct GroundStation {
    id: String,
    name: String,
    latitude_deg: f64,
    longitude_deg: f64,
    altitude_m: f64,
    min_elevation_deg: f64,
}

#[derive(Debug, Serialize)]
struct PropagateResponse {
    satellite_id: String,
    timestamp_unix: i64,
    position: Position,
    velocity: Velocity,
    geodetic: Geodetic,
    success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

// TASK-157: Batch response
#[derive(Debug, Serialize)]
struct BatchPropagateResponse {
    results: Vec<PropagateResponse>,
    total_count: usize,
    success_count: usize,
    error_count: usize,
}

// TASK-158: Trajectory response
#[derive(Debug, Serialize)]
struct TrajectoryResponse {
    satellite_id: String,
    points: Vec<TrajectoryPoint>,
    success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Debug, Serialize)]
struct TrajectoryPoint {
    timestamp_unix: i64,
    position: Position,
    velocity: Velocity,
    geodetic: Geodetic,
}

// TASK-159: Visibility response
#[derive(Debug, Serialize)]
struct VisibilityResponse {
    satellite_id: String,
    ground_station_id: String,
    passes: Vec<VisibilityPass>,
    success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Debug, Serialize)]
struct VisibilityPass {
    aos_timestamp: i64,    // Acquisition of signal
    los_timestamp: i64,    // Loss of signal
    max_elevation_deg: f64,
    duration_seconds: i64,
}

#[derive(Debug, Serialize)]
struct Position {
    x_km: f64,
    y_km: f64,
    z_km: f64,
}

#[derive(Debug, Serialize)]
struct Velocity {
    vx_km_s: f64,
    vy_km_s: f64,
    vz_km_s: f64,
}

#[derive(Debug, Serialize)]
struct Geodetic {
    latitude_deg: f64,
    longitude_deg: f64,
    altitude_km: f64,
}

// HTTP handler for propagation
async fn propagate_handler(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<PropagateRequest>,
) -> Result<Json<PropagateResponse>, (StatusCode, Json<PropagateResponse>)> {
    // TASK-163: Validate TLE format
    if req.tle_line1.len() != 69 || req.tle_line2.len() != 69 {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(PropagateResponse {
                satellite_id: req.satellite_id.clone(),
                timestamp_unix: req.timestamp_unix,
                position: Position { x_km: 0.0, y_km: 0.0, z_km: 0.0 },
                velocity: Velocity { vx_km_s: 0.0, vy_km_s: 0.0, vz_km_s: 0.0 },
                geodetic: Geodetic { latitude_deg: 0.0, longitude_deg: 0.0, altitude_km: 0.0 },
                success: false,
                error: Some("TLE lines must be exactly 69 characters".to_string()),
            }),
        ));
    }

    // TASK-164: Validate timestamp range
    let now = chrono::Utc::now().timestamp();
    if req.timestamp_unix < now - (365 * 24 * 3600) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(PropagateResponse {
                satellite_id: req.satellite_id.clone(),
                timestamp_unix: req.timestamp_unix,
                position: Position { x_km: 0.0, y_km: 0.0, z_km: 0.0 },
                velocity: Velocity { vx_km_s: 0.0, vy_km_s: 0.0, vz_km_s: 0.0 },
                geodetic: Geodetic { latitude_deg: 0.0, longitude_deg: 0.0, altitude_km: 0.0 },
                success: false,
                error: Some("Timestamp is more than 1 year in the past".to_string()),
            }),
        ));
    }

    // Update metrics
    {
        let mut app_state = state.write().await;
        app_state.metrics.increment_propagation_count();
    }

    match propagator::propagate(&req.tle_line1, &req.tle_line2, req.timestamp_unix) {
        Ok(result) => Ok(Json(PropagateResponse {
            satellite_id: req.satellite_id,
            timestamp_unix: req.timestamp_unix,
            position: Position {
                x_km: result.position_km[0],
                y_km: result.position_km[1],
                z_km: result.position_km[2],
            },
            velocity: Velocity {
                vx_km_s: result.velocity_km_s[0],
                vy_km_s: result.velocity_km_s[1],
                vz_km_s: result.velocity_km_s[2],
            },
            geodetic: Geodetic {
                latitude_deg: result.geodetic.latitude_deg,
                longitude_deg: result.geodetic.longitude_deg,
                altitude_km: result.geodetic.altitude_km,
            },
            success: true,
            error: None,
        })),
        Err(e) => {
            // Update error metrics
            {
                let mut app_state = state.write().await;
                app_state.metrics.increment_error_count();
            }

            Err((
                StatusCode::BAD_REQUEST,
                Json(PropagateResponse {
                    satellite_id: req.satellite_id,
                    timestamp_unix: req.timestamp_unix,
                    position: Position {
                        x_km: 0.0,
                        y_km: 0.0,
                        z_km: 0.0,
                    },
                    velocity: Velocity {
                        vx_km_s: 0.0,
                        vy_km_s: 0.0,
                        vz_km_s: 0.0,
                    },
                    geodetic: Geodetic {
                        latitude_deg: 0.0,
                        longitude_deg: 0.0,
                        altitude_km: 0.0,
                    },
                    success: false,
                    error: Some(e.to_string()),
                }),
            ))
        }
    }
}

// TASK-157: Batch propagation handler
async fn batch_propagate_handler(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(batch_req): Json<BatchPropagateRequest>,
) -> Json<BatchPropagateResponse> {
    let mut results = Vec::new();
    let mut success_count = 0;
    let mut error_count = 0;

    // TASK-162: Optimize for batch requests by reusing parsed elements where possible
    for req in batch_req.requests {
        // Validate TLE format
        if req.tle_line1.len() != 69 || req.tle_line2.len() != 69 {
            results.push(PropagateResponse {
                satellite_id: req.satellite_id,
                timestamp_unix: req.timestamp_unix,
                position: Position { x_km: 0.0, y_km: 0.0, z_km: 0.0 },
                velocity: Velocity { vx_km_s: 0.0, vy_km_s: 0.0, vz_km_s: 0.0 },
                geodetic: Geodetic { latitude_deg: 0.0, longitude_deg: 0.0, altitude_km: 0.0 },
                success: false,
                error: Some("TLE lines must be exactly 69 characters".to_string()),
            });
            error_count += 1;
            continue;
        }

        match propagator::propagate(&req.tle_line1, &req.tle_line2, req.timestamp_unix) {
            Ok(result) => {
                results.push(PropagateResponse {
                    satellite_id: req.satellite_id,
                    timestamp_unix: req.timestamp_unix,
                    position: Position {
                        x_km: result.position_km[0],
                        y_km: result.position_km[1],
                        z_km: result.position_km[2],
                    },
                    velocity: Velocity {
                        vx_km_s: result.velocity_km_s[0],
                        vy_km_s: result.velocity_km_s[1],
                        vz_km_s: result.velocity_km_s[2],
                    },
                    geodetic: Geodetic {
                        latitude_deg: result.geodetic.latitude_deg,
                        longitude_deg: result.geodetic.longitude_deg,
                        altitude_km: result.geodetic.altitude_km,
                    },
                    success: true,
                    error: None,
                });
                success_count += 1;
            }
            Err(e) => {
                results.push(PropagateResponse {
                    satellite_id: req.satellite_id,
                    timestamp_unix: req.timestamp_unix,
                    position: Position { x_km: 0.0, y_km: 0.0, z_km: 0.0 },
                    velocity: Velocity { vx_km_s: 0.0, vy_km_s: 0.0, vz_km_s: 0.0 },
                    geodetic: Geodetic { latitude_deg: 0.0, longitude_deg: 0.0, altitude_km: 0.0 },
                    success: false,
                    error: Some(e.to_string()),
                });
                error_count += 1;
            }
        }
    }

    // Update metrics
    {
        let mut app_state = state.write().await;
        app_state.metrics.add_propagation_count(success_count);
        app_state.metrics.add_error_count(error_count);
    }

    Json(BatchPropagateResponse {
        total_count: results.len(),
        success_count,
        error_count,
        results,
    })
}

// TASK-158: Trajectory propagation handler
async fn trajectory_handler(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<TrajectoryRequest>,
) -> Result<Json<TrajectoryResponse>, (StatusCode, Json<TrajectoryResponse>)> {
    // Validate TLE format
    if req.tle_line1.len() != 69 || req.tle_line2.len() != 69 {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(TrajectoryResponse {
                satellite_id: req.satellite_id,
                points: vec![],
                success: false,
                error: Some("TLE lines must be exactly 69 characters".to_string()),
            }),
        ));
    }

    // Validate time range
    if req.end_unix <= req.start_unix {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(TrajectoryResponse {
                satellite_id: req.satellite_id,
                points: vec![],
                success: false,
                error: Some("End time must be after start time".to_string()),
            }),
        ));
    }

    match propagator::propagate_trajectory(
        &req.tle_line1,
        &req.tle_line2,
        req.start_unix,
        req.end_unix,
        req.step_seconds,
    ) {
        Ok(trajectory) => {
            let points = trajectory
                .into_iter()
                .map(|(timestamp, result)| TrajectoryPoint {
                    timestamp_unix: timestamp,
                    position: Position {
                        x_km: result.position_km[0],
                        y_km: result.position_km[1],
                        z_km: result.position_km[2],
                    },
                    velocity: Velocity {
                        vx_km_s: result.velocity_km_s[0],
                        vy_km_s: result.velocity_km_s[1],
                        vz_km_s: result.velocity_km_s[2],
                    },
                    geodetic: Geodetic {
                        latitude_deg: result.geodetic.latitude_deg,
                        longitude_deg: result.geodetic.longitude_deg,
                        altitude_km: result.geodetic.altitude_km,
                    },
                })
                .collect();

            // Update metrics
            {
                let mut app_state = state.write().await;
                app_state.metrics.increment_propagation_count();
            }

            Ok(Json(TrajectoryResponse {
                satellite_id: req.satellite_id,
                points,
                success: true,
                error: None,
            }))
        }
        Err(e) => {
            {
                let mut app_state = state.write().await;
                app_state.metrics.increment_error_count();
            }

            Err((
                StatusCode::BAD_REQUEST,
                Json(TrajectoryResponse {
                    satellite_id: req.satellite_id,
                    points: vec![],
                    success: false,
                    error: Some(e.to_string()),
                }),
            ))
        }
    }
}

// TASK-159: Visibility calculation handler
async fn visibility_handler(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<VisibilityRequest>,
) -> Result<Json<VisibilityResponse>, (StatusCode, Json<VisibilityResponse>)> {
    // Validate TLE format
    if req.tle_line1.len() != 69 || req.tle_line2.len() != 69 {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(VisibilityResponse {
                satellite_id: req.satellite_id,
                ground_station_id: req.ground_station.id,
                passes: vec![],
                success: false,
                error: Some("TLE lines must be exactly 69 characters".to_string()),
            }),
        ));
    }

    match propagator::calculate_visibility(
        &req.tle_line1,
        &req.tle_line2,
        &req.ground_station.latitude_deg,
        &req.ground_station.longitude_deg,
        req.ground_station.altitude_m / 1000.0, // Convert to km
        req.ground_station.min_elevation_deg,
        req.start_unix,
        req.end_unix,
    ) {
        Ok(passes) => {
            let visibility_passes = passes
                .into_iter()
                .map(|pass| VisibilityPass {
                    aos_timestamp: pass.aos_timestamp,
                    los_timestamp: pass.los_timestamp,
                    max_elevation_deg: pass.max_elevation_deg,
                    duration_seconds: pass.los_timestamp - pass.aos_timestamp,
                })
                .collect();

            {
                let mut app_state = state.write().await;
                app_state.metrics.increment_propagation_count();
            }

            Ok(Json(VisibilityResponse {
                satellite_id: req.satellite_id,
                ground_station_id: req.ground_station.id,
                passes: visibility_passes,
                success: true,
                error: None,
            }))
        }
        Err(e) => {
            {
                let mut app_state = state.write().await;
                app_state.metrics.increment_error_count();
            }

            Err((
                StatusCode::BAD_REQUEST,
                Json(VisibilityResponse {
                    satellite_id: req.satellite_id,
                    ground_station_id: req.ground_station.id,
                    passes: vec![],
                    success: false,
                    error: Some(e.to_string()),
                }),
            ))
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Load .env file if present
    dotenvy::dotenv().ok();

    // Initialize tracing with JSON output for production
    let json_logs = std::env::var("JSON_LOGS")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    if json_logs {
        tracing_subscriber::registry()
            .with(EnvFilter::from_default_env().add_directive(Level::INFO.into()))
            .with(fmt::layer().json())
            .init();
    } else {
        tracing_subscriber::registry()
            .with(EnvFilter::from_default_env().add_directive(Level::INFO.into()))
            .with(fmt::layer())
            .init();
    }

    // Create shared application state
    let state = Arc::new(RwLock::new(AppState::new()));

    // Get configuration from environment
    let grpc_port: u16 = std::env::var("GRPC_PORT")
        .unwrap_or_else(|_| "50051".to_string())
        .parse()
        .expect("GRPC_PORT must be a valid port number");

    let metrics_port: u16 = std::env::var("METRICS_PORT")
        .unwrap_or_else(|_| "9090".to_string())
        .parse()
        .expect("METRICS_PORT must be a valid port number");

    let grpc_addr: SocketAddr = format!("0.0.0.0:{}", grpc_port).parse()?;
    let metrics_addr: SocketAddr = format!("0.0.0.0:{}", metrics_port).parse()?;

    info!("Starting Orbital Service v{}", env!("CARGO_PKG_VERSION"));
    info!("gRPC server listening on {}", grpc_addr);
    info!("Metrics server listening on {}", metrics_addr);

    // Create the gRPC service
    let orbital_service = OrbitalServiceImpl::new(Arc::clone(&state));

    // Start metrics HTTP server (also includes REST API)
    let metrics_state = Arc::clone(&state);
    let metrics_server = tokio::spawn(async move {
        let app = Router::new()
            .route("/metrics", get(metrics::metrics_handler))
            .route("/health", get(metrics::health_handler))
            .route("/api/propagate", post(propagate_handler))
            .route("/api/propagate/batch", post(batch_propagate_handler))  // TASK-157
            .route("/api/trajectory", post(trajectory_handler))  // TASK-158
            .route("/api/visibility", post(visibility_handler))  // TASK-159
            .with_state(metrics_state);

        let listener = tokio::net::TcpListener::bind(metrics_addr).await.unwrap();
        axum::serve(listener, app).await.unwrap();
    });

    // Start gRPC server
    let grpc_server = Server::builder()
        .add_service(OrbitalServiceServer::new(orbital_service))
        .serve(grpc_addr);

    // Run both servers concurrently
    tokio::select! {
        result = grpc_server => {
            if let Err(e) = result {
                tracing::error!("gRPC server error: {}", e);
            }
        }
        _ = metrics_server => {
            tracing::error!("Metrics server stopped unexpectedly");
        }
    }

    Ok(())
}
