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

#[derive(Debug, Deserialize)]
struct TrajectoryRequest {
    satellite_id: String,
    tle_line1: String,
    tle_line2: String,
    start_timestamp_unix: i64,
    end_timestamp_unix: i64,
    #[serde(default = "default_step")]
    step_seconds: i64,
}

fn default_step() -> i64 {
    60
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
    geodetic: Geodetic,
}

#[derive(Debug, Serialize, Clone)]
struct Position {
    x_km: f64,
    y_km: f64,
    z_km: f64,
}

#[derive(Debug, Serialize, Clone)]
struct Velocity {
    vx_km_s: f64,
    vy_km_s: f64,
    vz_km_s: f64,
}

#[derive(Debug, Serialize, Clone)]
struct Geodetic {
    latitude_deg: f64,
    longitude_deg: f64,
    altitude_km: f64,
}

// Visibility request/response types
#[derive(Debug, Deserialize)]
struct VisibilityHttpRequest {
    satellite_id: String,
    tle_line1: String,
    tle_line2: String,
    ground_station: GroundStationInput,
    start_timestamp_unix: i64,
    end_timestamp_unix: i64,
}

#[derive(Debug, Deserialize)]
struct GroundStationInput {
    id: String,
    name: String,
    latitude_deg: f64,
    longitude_deg: f64,
    altitude_m: f64,
    min_elevation_deg: f64,
}

#[derive(Debug, Serialize)]
struct VisibilityHttpResponse {
    satellite_id: String,
    ground_station_id: String,
    passes: Vec<PassInfo>,
    success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Debug, Serialize)]
struct PassInfo {
    aos_timestamp_unix: i64,
    los_timestamp_unix: i64,
    tca_timestamp_unix: i64,
    max_elevation_deg: f64,
    aos_azimuth_deg: f64,
    los_azimuth_deg: f64,
    duration_seconds: i64,
}

// HTTP handler for propagation
async fn propagate_handler(
    State(_state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<PropagateRequest>,
) -> Result<Json<PropagateResponse>, (StatusCode, Json<PropagateResponse>)> {
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
        Err(e) => Err((
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
        )),
    }
}

// HTTP handler for trajectory propagation
async fn trajectory_handler(
    State(_state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<TrajectoryRequest>,
) -> Result<Json<TrajectoryResponse>, (StatusCode, Json<TrajectoryResponse>)> {
    match propagator::propagate_trajectory(
        &req.tle_line1,
        &req.tle_line2,
        req.start_timestamp_unix,
        req.end_timestamp_unix,
        req.step_seconds,
    ) {
        Ok(results) => {
            let points: Vec<TrajectoryPoint> = results
                .into_iter()
                .map(|(ts, result)| TrajectoryPoint {
                    timestamp_unix: ts,
                    position: Position {
                        x_km: result.position_km[0],
                        y_km: result.position_km[1],
                        z_km: result.position_km[2],
                    },
                    geodetic: Geodetic {
                        latitude_deg: result.geodetic.latitude_deg,
                        longitude_deg: result.geodetic.longitude_deg,
                        altitude_km: result.geodetic.altitude_km,
                    },
                })
                .collect();

            Ok(Json(TrajectoryResponse {
                satellite_id: req.satellite_id,
                points,
                success: true,
                error: None,
            }))
        }
        Err(e) => Err((
            StatusCode::BAD_REQUEST,
            Json(TrajectoryResponse {
                satellite_id: req.satellite_id,
                points: vec![],
                success: false,
                error: Some(e.to_string()),
            }),
        )),
    }
}

// HTTP handler for visibility pass calculation
async fn visibility_handler(
    State(_state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<VisibilityHttpRequest>,
) -> Result<Json<VisibilityHttpResponse>, (StatusCode, Json<VisibilityHttpResponse>)> {
    let ground_station = propagator::GroundStation {
        id: req.ground_station.id.clone(),
        name: req.ground_station.name.clone(),
        latitude_deg: req.ground_station.latitude_deg,
        longitude_deg: req.ground_station.longitude_deg,
        altitude_m: req.ground_station.altitude_m,
        min_elevation_deg: req.ground_station.min_elevation_deg,
    };

    match propagator::calculate_visibility_passes(
        &req.tle_line1,
        &req.tle_line2,
        &ground_station,
        req.start_timestamp_unix,
        req.end_timestamp_unix,
    ) {
        Ok(passes) => {
            let pass_infos: Vec<PassInfo> = passes
                .into_iter()
                .map(|p| PassInfo {
                    aos_timestamp_unix: p.aos_timestamp,
                    los_timestamp_unix: p.los_timestamp,
                    tca_timestamp_unix: p.tca_timestamp,
                    max_elevation_deg: p.max_elevation_deg,
                    aos_azimuth_deg: p.aos_azimuth_deg,
                    los_azimuth_deg: p.los_azimuth_deg,
                    duration_seconds: p.duration_seconds,
                })
                .collect();

            Ok(Json(VisibilityHttpResponse {
                satellite_id: req.satellite_id,
                ground_station_id: req.ground_station.id,
                passes: pass_infos,
                success: true,
                error: None,
            }))
        }
        Err(e) => Err((
            StatusCode::BAD_REQUEST,
            Json(VisibilityHttpResponse {
                satellite_id: req.satellite_id,
                ground_station_id: req.ground_station.id,
                passes: vec![],
                success: false,
                error: Some(e.to_string()),
            }),
        )),
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
            .route("/api/trajectory", post(trajectory_handler))
            .route("/api/visibility", post(visibility_handler))
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
