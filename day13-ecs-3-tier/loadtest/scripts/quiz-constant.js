import http from 'k6/http';
import { sleep } from 'k6';
import {
  runLeaderboardStatsLoad,
  runLeaderboardTopicLoad,
  runQuizStart,
  runQuizSubmit,
  runTopicsLoad,
} from './helpers.js';

const defaultVus = Number(__ENV.VUS || 50);
const duration = __ENV.DURATION || '10m';

function vusFor(type) {
  const envKey = `VUS_${type.toUpperCase()}`;
  return Number(__ENV[envKey] || defaultVus);
}

export const options = {
  scenarios: {
    quiz_start: {
      executor: 'constant-vus',
      vus: vusFor('start'),
      duration,
      exec: 'quizStart',
      gracefulStop: '30s',
    },
    quiz_submit: {
      executor: 'constant-vus',
      vus: vusFor('submit'),
      duration,
      exec: 'quizSubmit',
      gracefulStop: '30s',
    },
    leaderboard_topic: {
      executor: 'constant-vus',
      vus: vusFor('leaderboard'),
      duration,
      exec: 'leaderboardTopic',
      gracefulStop: '30s',
    },
    leaderboard_stats: {
      executor: 'constant-vus',
      vus: vusFor('stats'),
      duration,
      exec: 'leaderboardStats',
      gracefulStop: '30s',
    },
    topics: {
      executor: 'constant-vus',
      vus: vusFor('topics'),
      duration,
      exec: 'topicsLoad',
      gracefulStop: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000'],
    'http_req_duration{name:quiz_start}': ['p(95)<1000'],
    'http_req_duration{name:quiz_submit}': ['p(95)<1500'],
    'http_req_duration{name:leaderboard_topic}': ['p(95)<800'],
    'http_req_duration{name:leaderboard_stats}': ['p(95)<800'],
    'http_req_duration{name:topics}': ['p(95)<600'],
  },
};

export function quizStart() {
  runQuizStart(http, sleep, __VU, __ITER);
}

export function quizSubmit() {
  runQuizSubmit(http, sleep, __VU, __ITER);
}

export function leaderboardTopic() {
  runLeaderboardTopicLoad(http, sleep);
}

export function leaderboardStats() {
  runLeaderboardStatsLoad(http, sleep);
}

export function topicsLoad() {
  runTopicsLoad(http, sleep);
}
