import http from 'k6/http';
import { sleep } from 'k6';
import {
  baseUrl,
  checkResponse,
  jsonHeaders,
  runQuizJourney,
  topicSlug,
} from './helpers.js';

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    http_req_failed: ['rate==0'],
    http_req_duration: ['p(95)<2000'],
  },
};

export default function () {
  const health = http.get(`${baseUrl()}/health`);
  checkResponse(health, 'health');

  const topics = http.get(`${baseUrl()}/api/topics`, { headers: jsonHeaders() });
  checkResponse(topics, 'topics');

  const ok = runQuizJourney(http, sleep, __VU, __ITER);
  if (ok) {
    console.log(`Smoke test passed against ${baseUrl()} topic=${topicSlug()}`);
  }
}
