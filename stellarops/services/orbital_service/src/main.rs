//! Orbital propagation service using SGP4
//!
//! This service provides gRPC endpoints for satellite position calculation
//! using Two-Line Element (TLE) sets and the SGP4 propagation algorithm.

mod generated;
mod metrics;
mod propagator;
mod service;

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;

use axum::{routing::get, Router};
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

    // Start metrics HTTP server
    let metrics_state = Arc::clone(&state);
    let metrics_server = tokio::spawn(async move {
        let app = Router::new()
            .route("/metrics", get(metrics::metrics_handler))
            .route("/health", get(metrics::health_handler))
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
