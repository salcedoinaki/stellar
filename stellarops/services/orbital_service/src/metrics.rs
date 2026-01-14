//! Prometheus metrics for the orbital service

use std::sync::Arc;
use std::time::Duration;

use axum::{extract::State, http::StatusCode, response::IntoResponse};
use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec, register_histogram_vec, CounterVec, Encoder, HistogramVec, TextEncoder,
};
use tokio::sync::RwLock;

use crate::AppState;

lazy_static! {
    /// Counter for gRPC requests by method and status
    pub static ref GRPC_REQUESTS: CounterVec = register_counter_vec!(
        "orbital_grpc_requests_total",
        "Total number of gRPC requests",
        &["method", "status"]
    ).unwrap();

    /// Histogram for propagation latency
    pub static ref PROPAGATION_LATENCY: HistogramVec = register_histogram_vec!(
        "orbital_propagation_seconds",
        "Time spent on propagation operations",
        &["method"],
        vec![0.0001, 0.0005, 0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0]
    ).unwrap();

    /// Counter for trajectory points generated
    pub static ref TRAJECTORY_POINTS: CounterVec = register_counter_vec!(
        "orbital_trajectory_points_total",
        "Total number of trajectory points generated",
        &["status"]
    ).unwrap();
}

/// Metrics state for recording from service handlers
pub struct MetricsState {
    // Can be extended with additional state if needed
}

impl MetricsState {
    pub fn new() -> Self {
        Self {}
    }

    pub fn record_propagation(&self, duration: Duration, success: bool) {
        let status = if success { "success" } else { "error" };
        
        GRPC_REQUESTS
            .with_label_values(&["PropagatePosition", status])
            .inc();
        
        PROPAGATION_LATENCY
            .with_label_values(&["propagate"])
            .observe(duration.as_secs_f64());
    }

    pub fn record_visibility(&self, duration: Duration, success: bool) {
        let status = if success { "success" } else { "error" };
        
        GRPC_REQUESTS
            .with_label_values(&["CalculateVisibility", status])
            .inc();
        
        PROPAGATION_LATENCY
            .with_label_values(&["visibility"])
            .observe(duration.as_secs_f64());
    }

    pub fn record_trajectory(&self, duration: Duration, points: usize, success: bool) {
        let status = if success { "success" } else { "error" };
        
        GRPC_REQUESTS
            .with_label_values(&["PropagateTrajectory", status])
            .inc();
        
        PROPAGATION_LATENCY
            .with_label_values(&["trajectory"])
            .observe(duration.as_secs_f64());

        TRAJECTORY_POINTS
            .with_label_values(&[status])
            .inc_by(points as f64);
    }
}

impl Default for MetricsState {
    fn default() -> Self {
        Self::new()
    }
}

/// Handler for /metrics endpoint (Prometheus format)
pub async fn metrics_handler() -> impl IntoResponse {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();
    
    let mut buffer = Vec::new();
    encoder.encode(&metric_families, &mut buffer).unwrap();
    
    (
        StatusCode::OK,
        [("content-type", "text/plain; version=0.0.4")],
        buffer,
    )
}

/// Handler for /health endpoint
pub async fn health_handler(
    State(state): State<Arc<RwLock<AppState>>>,
) -> impl IntoResponse {
    let state = state.read().await;
    let uptime = state.uptime_seconds();
    
    let body = serde_json::json!({
        "status": "healthy",
        "version": env!("CARGO_PKG_VERSION"),
        "uptime_seconds": uptime
    });
    
    (
        StatusCode::OK,
        [("content-type", "application/json")],
        serde_json::to_string(&body).unwrap(),
    )
}
