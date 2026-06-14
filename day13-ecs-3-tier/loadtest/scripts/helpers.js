import { check } from 'k6';

export const DEFAULT_BASE_URL = 'http://localhost:8000';
export const DEFAULT_TOPIC = 'docker';

export function baseUrl() {
  return __ENV.BASE_URL || DEFAULT_BASE_URL;
}

export function topicSlug() {
  return __ENV.TOPIC || DEFAULT_TOPIC;
}

export function jsonHeaders() {
  return { 'Content-Type': 'application/json', Accept: 'application/json' };
}

export function playerName(vu, iter) {
  const prefix = __ENV.PLAYER_PREFIX || 'loadtest';
  return `${prefix}_vu${vu}_iter${iter}`;
}

export function buildAnswers(questions, answerIndex = 0) {
  const answers = {};
  questions.forEach((question) => {
    answers[String(question.id)] = answerIndex;
  });
  return answers;
}

export function checkResponse(response, name) {
  return check(response, {
    [`${name} status 2xx`]: (r) => r.status >= 200 && r.status < 300,
  });
}

export function checkStartResponse(response) {
  const ok = check(response, {
    'start status 200': (r) => r.status === 200,
    'start has session_id': (r) => {
      try {
        return Boolean(r.json('session_id'));
      } catch {
        return false;
      }
    },
    'start has questions': (r) => {
      try {
        return Array.isArray(r.json('questions')) && r.json('questions').length > 0;
      } catch {
        return false;
      }
    },
    'start hides answers': (r) => {
      try {
        const questions = r.json('questions');
        return questions.every(
          (q) => q.correct_answer === undefined && q.correct_index === undefined
        );
      } catch {
        return false;
      }
    },
  });

  if (!ok) {
    return null;
  }

  return response.json();
}

export function checkSubmitResponse(response) {
  return check(response, {
    'submit status 200': (r) => r.status === 200,
    'submit has score': (r) => {
      try {
        return typeof r.json('score') === 'number';
      } catch {
        return false;
      }
    },
    'submit has rank': (r) => {
      try {
        return typeof r.json('rank') === 'number';
      } catch {
        return false;
      }
    },
  });
}

export function runQuizJourney(http, sleepFn, vu, iter) {
  const topic = topicSlug();
  const player = playerName(vu, iter);

  const startResponse = http.post(
    `${baseUrl()}/api/quiz/${topic}/start`,
    JSON.stringify({ player_name: player }),
    { headers: jsonHeaders(), tags: { name: 'quiz_start' } }
  );

  const quiz = checkStartResponse(startResponse);
  if (!quiz) {
    return false;
  }

  sleepFn(0.5);

  const submitResponse = http.post(
    `${baseUrl()}/api/quiz/submit`,
    JSON.stringify({
      session_id: quiz.session_id,
      answers: buildAnswers(quiz.questions),
      time_taken_seconds: 30 + (iter % 20),
    }),
    { headers: jsonHeaders(), tags: { name: 'quiz_submit' } }
  );

  if (!checkSubmitResponse(submitResponse)) {
    return false;
  }

  sleepFn(0.2);

  const leaderboardResponse = http.get(
    `${baseUrl()}/api/leaderboard?scope=topic&topic=${topic}&limit=20`,
    { tags: { name: 'leaderboard_topic' } }
  );

  checkResponse(leaderboardResponse, 'leaderboard');

  const statsResponse = http.get(`${baseUrl()}/api/leaderboard/stats`, {
    tags: { name: 'leaderboard_stats' },
  });

  checkResponse(statsResponse, 'stats');

  return true;
}
