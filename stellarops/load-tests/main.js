// StellarOps Load Test Suite
// Uses k6 for load testing (https://k6.io)
//
// Run with: k6 run load-tests/main.js
// Run with options: k6 run --vus 50 --duration 5m load-tests/main.js

import http from 'k6/http';
import ws from 'k6/ws';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const satelliteLatency = new Trend('satellite_latency');
const conjunctionLatency = new Trend('conjunction_latency');
const wsConnections = new Counter('websocket_connections');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';
const WS_URL = __ENV.WS_URL || 'ws://localhost:4000/socket/websocket';
const AUTH_TOKEN = __ENV.AUTH_TOKEN || '';

// Test options
export const options = {
  scenarios: {
    // Constant load for baseline
    constant_load: {
      executor: 'constant-vus',
      vus: 10,
      duration: '2m',
      gracefulStop: '30s',
    },
    // Ramping load to find limits
    ramp_up: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 20 },
        { duration: '2m', target: 50 },
        { duration: '2m', target: 100 },
        { duration: '1m', target: 0 },
      ],
      gracefulStop: '30s',
      startTime: '2m',
    },
    // Spike test
    spike: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '10s', target: 200 },
        { duration: '30s', target: 200 },
        { duration: '10s', target: 0 },
      ],
      startTime: '8m',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    errors: ['rate<0.01'],
    satellite_latency: ['p(95)<300'],
    conjunction_latency: ['p(95)<500'],
  },
};

// Helper function for authenticated requests
function authHeaders() {
  return {
    headers: {
      'Authorization': `Bearer ${AUTH_TOKEN}`,
      'Content-Type': 'application/json',
    },
  };
}

// Setup - runs once before tests
export function setup() {
  // Login and get token if not provided
  if (!AUTH_TOKEN) {
    const loginRes = http.post(`${BASE_URL}/api/auth/login`, JSON.stringify({
      email: 'loadtest@stellarops.com',
      password: 'LoadTest123!',
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
    
    if (loginRes.status === 200) {
      const body = JSON.parse(loginRes.body);
      return { token: body.token };
    }
  }
  
  return { token: AUTH_TOKEN };
}

// Main test function
export default function(data) {
  const token = data.token;
  const headers = {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  };
  
  group('Satellite API', () => {
    // List satellites
    const listStart = Date.now();
    const listRes = http.get(`${BASE_URL}/api/satellites`, headers);
    satelliteLatency.add(Date.now() - listStart);
    
    check(listRes, {
      'list satellites status 200': (r) => r.status === 200,
      'list satellites has data': (r) => JSON.parse(r.body).data !== undefined,
    });
    errorRate.add(listRes.status !== 200);
    
    // Get single satellite
    if (listRes.status === 200) {
      const satellites = JSON.parse(listRes.body).data;
      if (satellites.length > 0) {
        const satId = satellites[Math.floor(Math.random() * satellites.length)].id;
        const getRes = http.get(`${BASE_URL}/api/satellites/${satId}`, headers);
        
        check(getRes, {
          'get satellite status 200': (r) => r.status === 200,
        });
        errorRate.add(getRes.status !== 200);
      }
    }
  });
  
  group('Conjunction API', () => {
    const start = Date.now();
    const res = http.get(`${BASE_URL}/api/conjunctions?status=active`, headers);
    conjunctionLatency.add(Date.now() - start);
    
    check(res, {
      'list conjunctions status 200': (r) => r.status === 200,
      'conjunctions response time < 500ms': (r) => r.timings.duration < 500,
    });
    errorRate.add(res.status !== 200);
    
    // Get conjunction details
    if (res.status === 200) {
      const conjunctions = JSON.parse(res.body).data;
      if (conjunctions.length > 0) {
        const conjId = conjunctions[Math.floor(Math.random() * conjunctions.length)].id;
        const detailRes = http.get(`${BASE_URL}/api/conjunctions/${conjId}`, headers);
        
        check(detailRes, {
          'get conjunction status 200': (r) => r.status === 200,
        });
      }
    }
  });
  
  group('Mission API', () => {
    const res = http.get(`${BASE_URL}/api/missions?status=pending`, headers);
    
    check(res, {
      'list missions status 200': (r) => r.status === 200,
    });
    errorRate.add(res.status !== 200);
  });
  
  group('Alarm API', () => {
    const res = http.get(`${BASE_URL}/api/alarms?status=active`, headers);
    
    check(res, {
      'list alarms status 200': (r) => r.status === 200,
    });
    errorRate.add(res.status !== 200);
  });
  
  group('Space Objects API', () => {
    const res = http.get(`${BASE_URL}/api/objects?object_type=satellite&per_page=50`, headers);
    
    check(res, {
      'list objects status 200': (r) => r.status === 200,
    });
    errorRate.add(res.status !== 200);
  });
  
  sleep(1);
}

// WebSocket load test
export function websocket(data) {
  const token = data.token;
  
  const url = `${WS_URL}?token=${token}`;
  
  const res = ws.connect(url, {}, function(socket) {
    wsConnections.add(1);
    
    socket.on('open', () => {
      // Join satellite lobby channel
      socket.send(JSON.stringify({
        topic: 'satellite:lobby',
        event: 'phx_join',
        payload: {},
        ref: '1',
      }));
    });
    
    socket.on('message', (msg) => {
      const data = JSON.parse(msg);
      
      if (data.event === 'phx_reply' && data.payload.status === 'ok') {
        // Request all satellites
        socket.send(JSON.stringify({
          topic: 'satellite:lobby',
          event: 'get_all',
          payload: {},
          ref: '2',
        }));
      }
    });
    
    socket.on('error', (e) => {
      errorRate.add(true);
    });
    
    // Keep connection open for a while
    socket.setTimeout(() => {
      socket.close();
    }, 30000);
  });
  
  check(res, {
    'websocket connected': (r) => r && r.status === 101,
  });
}

// Teardown - runs once after tests
export function teardown(data) {
  // Cleanup if needed
  console.log('Load test completed');
}
