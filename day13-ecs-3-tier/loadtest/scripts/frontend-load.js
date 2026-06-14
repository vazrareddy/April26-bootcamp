import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 10,
  duration: '2m',
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<2000'],
  },
};

const FRONTEND_URL = __ENV.FRONTEND_URL || 'http://localhost:3000';

export default function () {
  const home = http.get(`${FRONTEND_URL}/`);
  check(home, { 'home 200': (r) => r.status === 200 });

  const topics = http.get(`${FRONTEND_URL}/api/topics`, {
    headers: { Accept: 'application/json' },
  });
  check(topics, { 'proxied topics 200': (r) => r.status === 200 });

  const leaderboard = http.get(`${FRONTEND_URL}/api/leaderboard/stats`, {
    headers: { Accept: 'application/json' },
  });
  check(leaderboard, { 'proxied stats 200': (r) => r.status === 200 });

  sleep(1);
}
