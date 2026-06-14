import http from 'k6/http';
import { sleep } from 'k6';
import { runQuizJourney } from './helpers.js';

export const options = {
  scenarios: {
    quiz_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },
        { duration: '2m', target: 10 },
        { duration: '30s', target: 25 },
        { duration: '1m', target: 25 },
        { duration: '30s', target: 0 },
      },
      gracefulRampDown: '15s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<1500'],
    'http_req_duration{name:quiz_start}': ['p(95)<800'],
    'http_req_duration{name:quiz_submit}': ['p(95)<1200'],
    'http_req_duration{name:leaderboard_topic}': ['p(95)<600'],
  },
};

export default function () {
  runQuizJourney(http, sleep, __VU, __ITER);
  sleep(1);
}
