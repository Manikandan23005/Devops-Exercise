import http from 'k6/http';
import { sleep, check } from 'k6';

// k6 Options configures the workload profiles
export const options = {
  stages: [
    { duration: '30s', target: 20 },  // Ramp up to 20 virtual users
    { duration: '1m', target: 30 },   // Increase to 30 virtual users and hold (triggering HPA scale up)
    { duration: '30s', target: 0 },   // Ramp down to 0 users
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'], // 95% of requests must complete under 2 seconds
  },
};

export default function () {
  // Hit the port-forwarded cpu-load-service endpoint
  const url = 'http://127.0.0.1:8080/load?duration=1.0';
  
  const res = http.get(url);
  
  // Validate that the request succeeded
  check(res, {
    'status is 200': (r) => r.status === 200,
    'contains calculations performed': (r) => r.body.includes('calculations_performed'),
  });
  
  sleep(1);
}
