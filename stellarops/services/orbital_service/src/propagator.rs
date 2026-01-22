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

/// Ground station location
#[derive(Debug, Clone)]
pub struct GroundStation {
    pub id: String,
    pub name: String,
    pub latitude_deg: f64,
    pub longitude_deg: f64,
    pub altitude_m: f64,
    pub min_elevation_deg: f64,
}

/// Visibility pass information
#[derive(Debug, Clone)]
pub struct VisibilityPass {
    pub aos_timestamp: i64,      // Acquisition of Signal
    pub los_timestamp: i64,      // Loss of Signal
    pub tca_timestamp: i64,      // Time of Closest Approach (max elevation)
    pub max_elevation_deg: f64,
    pub aos_azimuth_deg: f64,
    pub los_azimuth_deg: f64,
    pub duration_seconds: i64,
}

/// Calculate visibility passes for a satellite over a ground station
pub fn calculate_visibility_passes(
    tle_line1: &str,
    tle_line2: &str,
    ground_station: &GroundStation,
    start_unix: i64,
    end_unix: i64,
) -> Result<Vec<VisibilityPass>, PropagationError> {
    // Parse TLE once
    let elements = Elements::from_tle(
        None,
        tle_line1.as_bytes(),
        tle_line2.as_bytes(),
    ).map_err(|e| PropagationError::TleParseError(format!("{:?}", e)))?;

    let constants = Constants::from_elements(&elements)
        .map_err(|e| PropagationError::PropagatorError(format!("{:?}", e)))?;

    let tle_epoch_unix = tle_epoch_to_unix(&elements);

    // Convert ground station position to ECEF
    let gs_ecef = geodetic_to_ecef(
        ground_station.latitude_deg,
        ground_station.longitude_deg,
        ground_station.altitude_m / 1000.0, // Convert to km
    );

    let mut passes = Vec::new();
    let step_seconds: i64 = 30; // Check every 30 seconds for passes
    
    let mut in_pass = false;
    let mut current_pass_start: i64 = 0;
    let mut current_pass_start_azimuth: f64 = 0.0;
    let mut max_elevation: f64 = 0.0;
    let mut tca_timestamp: i64 = 0;

    let mut timestamp = start_unix;
    while timestamp <= end_unix {
        let minutes_since_epoch = (timestamp as f64 - tle_epoch_unix) / 60.0;

        if let Ok(prediction) = constants.propagate(minutes_since_epoch) {
            // Calculate elevation and azimuth from ground station
            let (elevation, azimuth) = calculate_look_angles(
                &prediction.position,
                &gs_ecef,
                ground_station.latitude_deg,
                ground_station.longitude_deg,
                timestamp,
            );

            let above_horizon = elevation >= ground_station.min_elevation_deg;

            if above_horizon && !in_pass {
                // Start of new pass
                in_pass = true;
                current_pass_start = timestamp;
                current_pass_start_azimuth = azimuth;
                max_elevation = elevation;
                tca_timestamp = timestamp;
            } else if above_horizon && in_pass {
                // Update max elevation
                if elevation > max_elevation {
                    max_elevation = elevation;
                    tca_timestamp = timestamp;
                }
            } else if !above_horizon && in_pass {
                // End of pass
                in_pass = false;
                
                // Re-calculate end azimuth
                let (_, end_azimuth) = calculate_look_angles(
                    &prediction.position,
                    &gs_ecef,
                    ground_station.latitude_deg,
                    ground_station.longitude_deg,
                    timestamp - step_seconds,
                );

                passes.push(VisibilityPass {
                    aos_timestamp: current_pass_start,
                    los_timestamp: timestamp,
                    tca_timestamp,
                    max_elevation_deg: max_elevation,
                    aos_azimuth_deg: current_pass_start_azimuth,
                    los_azimuth_deg: end_azimuth,
                    duration_seconds: timestamp - current_pass_start,
                });
            }
        }

        timestamp += step_seconds;
    }

    // Handle pass that extends beyond time window
    if in_pass {
        passes.push(VisibilityPass {
            aos_timestamp: current_pass_start,
            los_timestamp: end_unix,
            tca_timestamp,
            max_elevation_deg: max_elevation,
            aos_azimuth_deg: current_pass_start_azimuth,
            los_azimuth_deg: 0.0, // Unknown
            duration_seconds: end_unix - current_pass_start,
        });
    }

    debug!("Found {} visibility passes", passes.len());
    Ok(passes)
}

/// Convert geodetic coordinates to ECEF
fn geodetic_to_ecef(lat_deg: f64, lon_deg: f64, alt_km: f64) -> [f64; 3] {
    let lat_rad = lat_deg.to_radians();
    let lon_rad = lon_deg.to_radians();

    // WGS84 parameters
    let a = 6378.137; // Equatorial radius in km
    let f = 1.0 / 298.257223563;
    let e2 = 2.0 * f - f * f;

    let sin_lat = lat_rad.sin();
    let cos_lat = lat_rad.cos();
    let sin_lon = lon_rad.sin();
    let cos_lon = lon_rad.cos();

    let n = a / (1.0 - e2 * sin_lat * sin_lat).sqrt();

    let x = (n + alt_km) * cos_lat * cos_lon;
    let y = (n + alt_km) * cos_lat * sin_lon;
    let z = (n * (1.0 - e2) + alt_km) * sin_lat;

    [x, y, z]
}

/// Calculate look angles (elevation, azimuth) from ground station to satellite
fn calculate_look_angles(
    sat_eci: &[f64; 3],
    gs_ecef: &[f64; 3],
    gs_lat_deg: f64,
    gs_lon_deg: f64,
    timestamp_unix: i64,
) -> (f64, f64) {
    // Convert satellite ECI to ECEF
    let gmst = calculate_gmst(timestamp_unix);
    let cos_gmst = gmst.cos();
    let sin_gmst = gmst.sin();

    let sat_ecef = [
        sat_eci[0] * cos_gmst + sat_eci[1] * sin_gmst,
        -sat_eci[0] * sin_gmst + sat_eci[1] * cos_gmst,
        sat_eci[2],
    ];

    // Vector from ground station to satellite in ECEF
    let range_ecef = [
        sat_ecef[0] - gs_ecef[0],
        sat_ecef[1] - gs_ecef[1],
        sat_ecef[2] - gs_ecef[2],
    ];

    // Convert to topocentric coordinates (SEZ - South, East, Zenith)
    let lat_rad = gs_lat_deg.to_radians();
    let lon_rad = gs_lon_deg.to_radians();

    let sin_lat = lat_rad.sin();
    let cos_lat = lat_rad.cos();
    let sin_lon = lon_rad.sin();
    let cos_lon = lon_rad.cos();

    // Rotation matrix ECEF to SEZ
    let s = sin_lat * cos_lon * range_ecef[0] + sin_lat * sin_lon * range_ecef[1] - cos_lat * range_ecef[2];
    let e = -sin_lon * range_ecef[0] + cos_lon * range_ecef[1];
    let z = cos_lat * cos_lon * range_ecef[0] + cos_lat * sin_lon * range_ecef[1] + sin_lat * range_ecef[2];

    let range = (s * s + e * e + z * z).sqrt();

    // Elevation angle
    let elevation_rad = (z / range).asin();
    let elevation_deg = elevation_rad.to_degrees();

    // Azimuth angle (from North, clockwise)
    let azimuth_rad = (-s).atan2(e);
    let mut azimuth_deg = azimuth_rad.to_degrees();
    if azimuth_deg < 0.0 {
        azimuth_deg += 360.0;
    }

    (elevation_deg, azimuth_deg)
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
