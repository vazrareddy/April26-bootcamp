#!/usr/bin/env bash
set -euo pipefail

# Live app URL (ALB → frontend → backend via Service Connect proxy).
# Override if your deployed subdomain differs:
#   APP_URL=https://your-subdomain.example.com ./run-live.sh smoke
export APP_URL="${APP_URL:-https://devopsdojo.livingdevops.org}"
export BASE_URL="${BASE_URL:-$APP_URL}"
export FRONTEND_URL="${FRONTEND_URL:-$APP_URL}"
export TOPIC="${TOPIC:-docker}"
export PLAYER_PREFIX="${PLAYER_PREFIX:-loadtest}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [smoke|load|stress|frontend]

Load-test the LIVE deployed app through the public ALB/frontend URL.

Default target: ${APP_URL}

All quiz API traffic goes through the frontend proxy:
  ${APP_URL}/api/quiz/...
  ${APP_URL}/api/leaderboard/...

Environment variables:
  APP_URL         Public app URL (default: https://devopsdojo.livingdevops.org)
  TOPIC           Quiz topic slug (default: docker)
  PLAYER_PREFIX   Leaderboard name prefix (default: loadtest)

Examples:
  $(basename "$0") smoke
  TOPIC=kubernetes $(basename "$0") load
  APP_URL=https://devopsdojo.livingdevops.org $(basename "$0") stress

Important:
  - Start with smoke, then load. Avoid stress on shared dev unless you intend to.
  - Loadtest player names appear on the live leaderboard (prefix: ${PLAYER_PREFIX}_*).
EOF
}

preflight() {
  echo "Target: ${APP_URL}"
  echo "Checking reachability..."
  if ! curl -sf "${APP_URL}/health" >/dev/null; then
    echo "Could not reach ${APP_URL}/health"
    echo "Verify the app is deployed and DNS is correct."
    exit 1
  fi
  if ! curl -sf "${APP_URL}/api/topics" >/dev/null; then
    echo "Could not reach ${APP_URL}/api/topics"
    exit 1
  fi
  echo "Live app is reachable."
  echo ""
}

run_k6() {
  local script="$1"
  if ! command -v k6 >/dev/null 2>&1; then
    echo "k6 is required for live endpoint testing."
    echo "Install: brew install k6"
    exit 1
  fi
  k6 run "${ROOT_DIR}/scripts/${script}"
}

SCRIPT="${1:-smoke}"

case "${SCRIPT}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

preflight

case "${SCRIPT}" in
  smoke)   run_k6 smoke.js ;;
  load)    run_k6 quiz-load.js ;;
  stress)  run_k6 quiz-stress.js ;;
  frontend) run_k6 frontend-load.js ;;
  *)
    echo "Unknown script: ${SCRIPT}"
    usage
    exit 1
    ;;
esac
