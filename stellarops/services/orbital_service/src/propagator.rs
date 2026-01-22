//! SGP4 orbital propagation implementation

use chrono::{Datelike, TimeZone, Timelike, Utc};
use sgp4::{Constants, Elements};
use tracing::{debug, warn};

/// Result of orbital propagation
#[derive(Debug, Clone)]
pub struct PropagationResult {
    pub position_km: [f64; 3],   // ECI position [x, y, z] in km
    pub velocity_km_s: [f64; 3], // ECI velocity [vx, vy, vz] in km/s
    pub geodetic: GeodeticCoords,
}

/// Geodetic coordinates
#[derive(Debug, Clone)]
pub struct GeodeticCoords {
    pub latitude_deg: f64,
    pub longitude_deg: f64,
    pub altitude_km: f64,
}

/// Parse TLE and propagate to given timestamp
pub fn propagate(
    tle_line1: &str,
    tle_line2: &str,
    timestamp_unix: i64,
) -> Result<PropagationResult, PropagationError> {
    // Parse TLE
    let elements = Elements::from_tle(
        None,
        tle_line1.as_bytes(),
        tle_line2.as_bytes(),
    ).map_err(|e| PropagationError::TleParseError(format!("{:?}", e)))?;

    debug!(
        "Parsed TLE for NORAD ID: {}, epoch: {:?}",
        elements.norad_id, elements.datetime
    );

    // Create propagator with WGS84 constants
    let constants = Constants::from_elements(&elements)
        .map_err(|e| PropagationError::PropagatorError(format!("{:?}", e)))?;

    // Calculate time since TLE epoch in minutes
    let tle_epoch_unix = tle_epoch_to_unix(&elements);
    let minutes_since_epoch = (timestamp_unix as f64 - tle_epoch_unix) / 60.0;

    debug!(
        "Propagating {} minutes from epoch",
        minutes_since_epoch
    );

    // Propagate
    let prediction = constants
        .propagate(minutes_since_epoch)
        .map_err(|e| PropagationError::PropagatorError(format!("{:?}", e)))?;

    // Extract position and velocity
    let position_km = prediction.position;
    let velocity_km_s = prediction.velocity;

    // Convert to geodetic
    let geodetic = eci_to_geodetic(&position_km, timestamp_unix);

    Ok(PropagationResult {
        position_km,
        velocity_km_s,
        geodetic,
    })
}

/// Propagate trajectory over a time range
pub fn propagate_trajectory(
    tle_line1: &str,
    tle_line2: &str,
    start_unix: i64,
    end_unix: i64,
    step_seconds: i64,
) -> Result<Vec<(i64, PropagationResult)>, PropagationError> {
    let elements = Elements::from_tle(
        None,
        tle_line1.as_bytes(),
        tle_line2.as_bytes(),
    ).map_err(|e| PropagationError::TleParseError(format!("{:?}", e)))?;

    let constants = Constants::from_elements(&elements)
        .map_err(|e| PropagationError::PropagatorError(format!("{:?}", e)))?;

    let tle_epoch_unix = tle_epoch_to_unix(&elements);
    let mut results = Vec::new();

    let mut timestamp = start_unix;
    while timestamp <= end_unix {
        let minutes_since_epoch = (timestamp as f64 - tle_epoch_unix) / 60.0;

        match constants.propagate(minutes_since_epoch) {
            Ok(prediction) => {
                let geodetic = eci_to_geodetic(&prediction.position, timestamp);
                results.push((
                    timestamp,
                    PropagationResult {
                        position_km: prediction.position,
                        velocity_km_s: prediction.velocity,
                        geodetic,
                    },
                ));
            }
            Err(e) => {
                warn!("Propagation failed at timestamp {}: {:?}", timestamp, e);
            }
        }

        timestamp += step_seconds;
    }

    Ok(results)
}

/// TASK-159: Visibility pass data
#[derive(Debug, Clone)]
pub struct VisibilityPass {
    pub aos_timestamp: i64,
    pub los_timestamp: i64,
    pub max_elevation_deg: f64,
}

/// TASK-159: Calculate visibility passes for a ground station
pub fn calculate_visibility(
    tle_line1: &str,
    tle_line2: &str,
    gs_lat_deg: &f64,
    gs_lon_deg: &f64,
    gs_alt_km: f64,
    min_elevation_deg: f64,
    start_unix: i64,
    end_unix: i64,
) -> Result<Vec<VisibilityPass>, PropagationError> {
    // Generate trajectory with 10-second steps for visibility calculation
    let trajectory = propagate_trajectory(tle_line1, tle_line2, start_unix, end_unix, 10)?;

    let mut passes = Vec::new();
    let mut in_pass = false;
    let mut pass_start: i64 = 0;
    let mut max_elevation = 0.0;

    for (timestamp, result) in trajectory {
        let elevation = calculate_elevation(
            &result.position_km,
            *gs_lat_deg,
            *gs_lon_deg,
            gs_alt_km,
            timestamp,
        );

        if elevation >= min_elevation_deg {
            if !in_pass {
                // Start of pass
                in_pass = true;
                pass_start = timestamp;
                max_elevation = elevation;
            } else {
                // Update max elevation
                if elevation > max_elevation {
                    max_elevation = elevation;
                }
            }
        } else if in_pass {
            // End of pass
            passes.push(VisibilityPass {
                aos_timestamp: pass_start,
                los_timestamp: timestamp,
                max_elevation_deg: max_elevation,
            });
            in_pass = false;
        }
    }

    // Handle case where pass is still active at end of time range
    if in_pass {
        passes.push(VisibilityPass {
            aos_timestamp: pass_start,
            los_timestamp: end_unix,
            max_elevation_deg: max_elevation,
        });
    }

    Ok(passes)
}

/// Calculate elevation angle from ground station to satellite
fn calculate_elevation(
    sat_position_eci: &[f64; 3],
    gs_lat_deg: f64,
    gs_lon_deg: f64,
    gs_alt_km: f64,
    timestamp: i64,
) -> f64 {
    // Convert ground station to ECEF
    let gs_ecef = geodetic_to_ecef(gs_lat_deg, gs_lon_deg, gs_alt_km);

    // Convert satellite ECI to ECEF
    let gmst = calculate_gmst(timestamp);
    let cos_gmst = gmst.cos();
    let sin_gmst = gmst.sin();
    let sat_ecef = [
        sat_position_eci[0] * cos_gmst + sat_position_eci[1] * sin_gmst,
        -sat_position_eci[0] * sin_gmst + sat_position_eci[1] * cos_gmst,
        sat_position_eci[2],
    ];

    // Range vector from ground station to satellite
    let range = [
        sat_ecef[0] - gs_ecef[0],
        sat_ecef[1] - gs_ecef[1],
        sat_ecef[2] - gs_ecef[2],
    ];

    // Convert to SEZ (South-East-Zenith) coordinates
    let lat_rad = gs_lat_deg.to_radians();
    let lon_rad = gs_lon_deg.to_radians();

    let sin_lat = lat_rad.sin();
    let cos_lat = lat_rad.cos();
    let sin_lon = lon_rad.sin();
    let cos_lon = lon_rad.cos();

    // Rotation matrix to SEZ
    let s = sin_lat * cos_lon * range[0] + sin_lat * sin_lon * range[1] - cos_lat * range[2];
    let e = -sin_lon * range[0] + cos_lon * range[1];
    let z = cos_lat * cos_lon * range[0] + cos_lat * sin_lon * range[1] + sin_lat * range[2];

    // Calculate elevation
    let range_magnitude = (s * s + e * e + z * z).sqrt();
    let elevation_rad = (z / range_magnitude).asin();
    elevation_rad.to_degrees()
}

/// Convert geodetic coordinates to ECEF
fn geodetic_to_ecef(lat_deg: f64, lon_deg: f64, alt_km: f64) -> [f64; 3] {
    let lat_rad = lat_deg.to_radians();
    let lon_rad = lon_deg.to_radians();

    const A: f64 = 6378.137; // WGS84 equatorial radius in km
    const E2: f64 = 0.00669437999014; // WGS84 first eccentricity squared

    let sin_lat = lat_rad.sin();
    let cos_lat = lat_rad.cos();
    let sin_lon = lon_rad.sin();
    let cos_lon = lon_rad.cos();

    let n = A / (1.0 - E2 * sin_lat * sin_lat).sqrt();

    [
        (n + alt_km) * cos_lat * cos_lon,
        (n + alt_km) * cos_lat * sin_lon,
        (n * (1.0 - E2) + alt_km) * sin_lat,
    ]
}

/// Convert TLE epoch to Unix timestamp
fn tle_epoch_to_unix(elements: &Elements) -> f64 {
    // TLE epoch is in UTC
    let dt = elements.datetime;
    
    let datetime = Utc
        .with_ymd_and_hms(
            dt.year() as i32,
            dt.month() as u32,
            dt.day() as u32,
            dt.hour() as u32,
            dt.minute() as u32,
            dt.second() as u32,
        )
        .single()
        .expect("Invalid datetime");
    
    // Add nanoseconds
    let nanos = dt.nanosecond() as i64;
    datetime.timestamp() as f64 + (nanos as f64 / 1_000_000_000.0)
}

/// Convert ECI position to geodetic coordinates
/// Simplified implementation - for production, use a proper geodetic library
fn eci_to_geodetic(position_km: &[f64; 3], timestamp_unix: i64) -> GeodeticCoords {
    let x = position_km[0];
    let y = position_km[1];
    let z = position_km[2];

    // WGS84 parameters
    let a = 6378.137; // Equatorial radius in km
    let f = 1.0 / 298.257223563; // Flattening
    let e2 = 2.0 * f - f * f; // First eccentricity squared

    // Calculate GMST (Greenwich Mean Sidereal Time) for longitude
    let gmst = calculate_gmst(timestamp_unix);

    // ECI to ECEF rotation (simplified)
    let cos_gmst = gmst.cos();
    let sin_gmst = gmst.sin();
    let x_ecef = x * cos_gmst + y * sin_gmst;
    let y_ecef = -x * sin_gmst + y * cos_gmst;
    let z_ecef = z;

    // Longitude
    let longitude_rad = y_ecef.atan2(x_ecef);
    let longitude_deg = longitude_rad.to_degrees();

    // Iterative latitude calculation
    let p = (x_ecef * x_ecef + y_ecef * y_ecef).sqrt();
    let mut latitude_rad = z_ecef.atan2(p);

    for _ in 0..10 {
        let sin_lat = latitude_rad.sin();
        let n = a / (1.0 - e2 * sin_lat * sin_lat).sqrt();
        latitude_rad = (z_ecef + e2 * n * sin_lat).atan2(p);
    }

    let latitude_deg = latitude_rad.to_degrees();

    // Altitude
    let sin_lat = latitude_rad.sin();
    let cos_lat = latitude_rad.cos();
    let n = a / (1.0 - e2 * sin_lat * sin_lat).sqrt();
    let altitude_km = if cos_lat.abs() > 1e-10 {
        p / cos_lat - n
    } else {
        z_ecef.abs() / sin_lat.abs() - n * (1.0 - e2)
    };

    GeodeticCoords {
        latitude_deg,
        longitude_deg,
        altitude_km,
    }
}

/// Calculate Greenwich Mean Sidereal Time in radians
fn calculate_gmst(timestamp_unix: i64) -> f64 {
    // Julian date at Unix epoch (1970-01-01 00:00:00 UTC)
    const JD_UNIX_EPOCH: f64 = 2440587.5;
    
    // Convert Unix timestamp to Julian date
    let jd = JD_UNIX_EPOCH + (timestamp_unix as f64 / 86400.0);
    
    // Julian centuries from J2000.0
    let t = (jd - 2451545.0) / 36525.0;
    
    // GMST in degrees
    let gmst_deg = 280.46061837 
        + 360.98564736629 * (jd - 2451545.0)
        + 0.000387933 * t * t 
        - t * t * t / 38710000.0;
    
    // Normalize to [0, 360)
    let gmst_normalized = ((gmst_deg % 360.0) + 360.0) % 360.0;
    
    gmst_normalized.to_radians()
}

/// Propagation errors
#[derive(Debug, Clone)]
pub enum PropagationError {
    TleParseError(String),
    PropagatorError(String),
    InvalidTimestamp(String),
}

impl std::fmt::Display for PropagationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PropagationError::TleParseError(msg) => write!(f, "TLE parse error: {}", msg),
            PropagationError::PropagatorError(msg) => write!(f, "Propagation error: {}", msg),
            PropagationError::InvalidTimestamp(msg) => write!(f, "Invalid timestamp: {}", msg),
        }
    }
}

impl std::error::Error for PropagationError {}

#[cfg(test)]
mod tests {
    use super::*;

    // ISS TLE (example - will be outdated)
    const ISS_TLE_LINE1: &str = "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9025";
    const ISS_TLE_LINE2: &str = "2 25544  51.6400 208.9163 0006703 130.5360 325.0288 15.50377579999999";

    #[test]
    fn test_propagate_iss() {
        // Use a timestamp close to the TLE epoch
        let timestamp = 1704067200; // 2024-01-01 00:00:00 UTC

        let result = propagate(ISS_TLE_LINE1, ISS_TLE_LINE2, timestamp);
        
        match result {
            Ok(prop) => {
                // ISS should be in LEO
                let altitude = prop.geodetic.altitude_km;
                assert!(altitude > 350.0, "ISS altitude should be > 350 km, got {}", altitude);
                assert!(altitude < 450.0, "ISS altitude should be < 450 km, got {}", altitude);
                
                // Latitude should be within ISS inclination
                assert!(prop.geodetic.latitude_deg.abs() <= 52.0, 
                    "Latitude should be within inclination, got {}", prop.geodetic.latitude_deg);
            }
            Err(e) => {
                panic!("Propagation failed: {}", e);
            }
        }
    }

    #[test]
    fn test_propagate_trajectory() {
        let start = 1704067200;
        let end = start + 3600; // 1 hour
        let step = 60; // 1 minute

        let result = propagate_trajectory(
            ISS_TLE_LINE1,
            ISS_TLE_LINE2,
            start,
            end,
            step,
        );

        match result {
            Ok(points) => {
                assert_eq!(points.len(), 61); // 0 to 60 minutes inclusive
            }
            Err(e) => {
                panic!("Trajectory propagation failed: {}", e);
            }
        }
    }
}
