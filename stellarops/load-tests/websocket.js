// StellarOps WebSocket Load Test
// Tests real-time communication under load

import ws from 'k6/ws';
import { check, sleep } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';

const wsMessages = new Counter('ws_messages_received');
const wsLatency = new Trend('ws_message_latency');
const wsErrors = new Rate('ws_errors');
const wsConnected = new Counter('ws_connections');

const WS_URL = __ENV.WS_URL || 'ws://localhost:4000/socket/websocket';
const AUTH_TOKEN = __ENV.AUTH_TOKEN || '';

export const options = {
  scenarios: {
    // Many concurrent WebSocket connections
    concurrent_connections: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 100 },
        { duration: '2m', target: 100 },
        { duration: '30s', target: 500 },
        { duration: '2m', target: 500 },
        { duration: '30s', target: 0 },
      ],
    },
  },
  thresholds: {
    ws_errors: ['rate<0.05'],
    ws_message_latency: ['p(95)<100'],
  },
};

export default function() {
  const url = `${WS_URL}?token=${AUTH_TOKEN}&vsn=2.0.0`;
  
  const res = ws.connect(url, {}, function(socket) {
    let joinRef = 0;
    let messageRef = 0;
    let lastMessageTime = Date.now();
    
    socket.on('open', () => {
      wsConnected.add(1);
      
      // Join satellite lobby
      joinRef++;
      socket.send(JSON.stringify([
        joinRef.toString(),
        joinRef.toString(),
        'satellite:lobby',
        'phx_join',
        {}
      ]));
    });
    
    socket.on('message', (msg) => {
      const now = Date.now();
      wsLatency.add(now - lastMessageTime);
      lastMessageTime = now;
      wsMessages.add(1);
      
      try {
        const data = JSON.parse(msg);
        
        // Handle different message types
        if (Array.isArray(data)) {
          const [, , topic, event, payload] = data;
          
          if (event === 'phx_reply' && payload.status === 'ok') {
            // Successfully joined, request data
            messageRef++;
            socket.send(JSON.stringify([
              null,
              messageRef.toString(),
              'satellite:lobby',
              'get_all',
              {}
            ]));
          }
          
          if (event === 'satellite_update') {
            // Handle real-time update
            wsMessages.add(1);
          }
        }
      } catch (e) {
        wsErrors.add(true);
      }
    });
    
    socket.on('error', (e) => {
      wsErrors.add(true);
    });
    
    socket.on('close', () => {
      // Connection closed
    });
    
    // Send heartbeat every 30 seconds
    socket.setInterval(() => {
      socket.send(JSON.stringify([
        null,
        (++messageRef).toString(),
        'phoenix',
        'heartbeat',
        {}
      ]));
    }, 30000);
    
    // Keep connection open for test duration
    socket.setTimeout(() => {
      // Leave channel gracefully
      socket.send(JSON.stringify([
        joinRef.toString(),
        (++messageRef).toString(),
        'satellite:lobby',
        'phx_leave',
        {}
      ]));
      
      sleep(1);
      socket.close();
    }, 120000); // 2 minutes
  });
  
  check(res, {
    'WebSocket connected': (r) => r && r.status === 101,
  });
  
  if (!res || res.status !== 101) {
    wsErrors.add(true);
  }
}
