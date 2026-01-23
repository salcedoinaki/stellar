// StellarOps Conjunction Detection Load Test
// Tests the conjunction detection system under load

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const propagationLatency = new Trend('propagation_latency');
const detectionLatency = new Trend('detection_latency');
const propagationErrors = new Counter('propagation_errors');

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';
const ORBITAL_URL = __ENV.ORBITAL_URL || 'http://localhost:9090';
const AUTH_TOKEN = __ENV.AUTH_TOKEN || '';

export const options = {
  scenarios: {
    // Simulate multiple satellites needing propagation
    propagation_load: {
      executor: 'constant-arrival-rate',
      rate: 100,
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 50,
      maxVUs: 100,
    },
  },
  thresholds: {
    propagation_latency: ['p(95)<200', 'p(99)<500'],
    propagation_errors: ['count<10'],
  },
};

// Sample TLE data for testing
const SAMPLE_TLES = [
  {
    satellite_id: 'ISS',
    line1: '1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993',
    line2: '2 25544  51.6400 123.4567 0006789 123.4567 234.5678 15.54321234567890',
  },
  {
    satellite_id: 'STARLINK-1234',
    line1: '1 44713U 19074A   24001.50000000  .00000500  00000-0  35000-4 0  9991',
    line2: '2 44713  53.0000 150.0000 0001234  90.0000 270.0000 15.05000000 12345',
  },
  {
    satellite_id: 'GPS-IIR-10',
    line1: '1 28874U 05038A   24001.50000000 -.00000012  00000-0  00000-0 0  9999',
    line2: '2 28874  55.0000  60.0000 0100000 270.0000  90.0000  2.00570000 12345',
  },
];

export default function() {
  const tle = SAMPLE_TLES[Math.floor(Math.random() * SAMPLE_TLES.length)];
  const timestamp = Math.floor(Date.now() / 1000);
  
  group('Orbital Propagation', () => {
    const start = Date.now();
    
    const payload = {
      satellite_id: tle.satellite_id,
      tle: {
        line1: tle.line1,
        line2: tle.line2,
      },
      timestamp_unix: timestamp,
    };
    
    const res = http.post(`${ORBITAL_URL}/propagate`, JSON.stringify(payload), {
      headers: { 'Content-Type': 'application/json' },
    });
    
    propagationLatency.add(Date.now() - start);
    
    const success = check(res, {
      'propagation status 200': (r) => r.status === 200,
      'propagation has position': (r) => {
        if (r.status !== 200) return false;
        const body = JSON.parse(r.body);
        return body.position !== undefined;
      },
      'propagation latency < 100ms': (r) => r.timings.duration < 100,
    });
    
    if (!success) {
      propagationErrors.add(1);
    }
  });
  
  group('Batch Propagation', () => {
    const start = Date.now();
    
    const payload = {
      requests: SAMPLE_TLES.map(tle => ({
        satellite_id: tle.satellite_id,
        tle: {
          line1: tle.line1,
          line2: tle.line2,
        },
        timestamp_unix: timestamp,
      })),
    };
    
    const res = http.post(`${ORBITAL_URL}/propagate/batch`, JSON.stringify(payload), {
      headers: { 'Content-Type': 'application/json' },
    });
    
    check(res, {
      'batch propagation status 200': (r) => r.status === 200,
      'batch has all results': (r) => {
        if (r.status !== 200) return false;
        const body = JSON.parse(r.body);
        return body.results && body.results.length === SAMPLE_TLES.length;
      },
    });
  });
  
  group('Trajectory Generation', () => {
    const tle = SAMPLE_TLES[0];
    const start_ts = timestamp;
    const end_ts = timestamp + 3600; // 1 hour
    
    const payload = {
      satellite_id: tle.satellite_id,
      tle: {
        line1: tle.line1,
        line2: tle.line2,
      },
      start_timestamp_unix: start_ts,
      end_timestamp_unix: end_ts,
      step_seconds: 60,
    };
    
    const res = http.post(`${ORBITAL_URL}/trajectory`, JSON.stringify(payload), {
      headers: { 'Content-Type': 'application/json' },
    });
    
    check(res, {
      'trajectory status 200': (r) => r.status === 200,
      'trajectory has points': (r) => {
        if (r.status !== 200) return false;
        const body = JSON.parse(r.body);
        return body.points && body.points.length > 0;
      },
      'trajectory has expected point count': (r) => {
        if (r.status !== 200) return false;
        const body = JSON.parse(r.body);
        // 1 hour / 60 second steps = 60 points (+1 for start)
        return body.points && body.points.length >= 60;
      },
    });
  });
  
  sleep(0.1);
}
