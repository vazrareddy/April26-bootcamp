

#!/usr/bin/env bash
set -euo pipefail

# VUS=200 VUS_START=60 VUS_STATS=40 DURATION=10m ./run-live.sh constant

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${ROOT_DIR}/../app"
SCRIPT="${1:-smoke}"xwww
BASE_URL="${BASE_URL:-http://localhost:8000}"
TOPIC="${TOPIC:-docker}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [smoke|load|stress|frontend]

Runs k6 load tests against the local compose stack.

Environment variables:
  BASE_URL       Backend URL (default: http://localhost:8000)
  FRONTEND_URL   Frontend URL for frontend-load.js (default: http://localhost:3000)
  TOPIC          Quiz topic slug (default: docker)
  PLAYER_PREFIX  Prefix for generated player names (default: loadtest)

Examples:
  $(basename "$0") smoke
  $(basename "$0") load
  BASE_URL=http://localhost:8000 TOPIC=kubernetes $(basename "$0") stress
EOF
}

ensure_app_running() {
  if [[ "${BASE_URL}" == http://localhost:* ]] || [[ "${BASE_URL}" == https://localhost:* ]]; then
    if ! curl -sf "${BASE_URL}/health" >/dev/null; then
      echo "Backend is not reachable at ${BASE_URL}"
      echo "Start the app first:"
      echo "  cd ${APP_DIR} && docker compose up --build -d"
      exit 1
    fi
  fi
}

run_with_k6() {
  local script_file="$1"
  shift
  k6 run "$@" "${ROOT_DIR}/scripts/${script_file}"
}

run_with_docker() {
  local script_file="$1"
  shift
  local docker_base_url="${BASE_URL}"
  if [[ "${docker_base_url}" == "http://localhost:8000" ]]; then
    docker_base_url="http://backend:8000"
  fi
  docker run --rm -i \
    --network app_default \
    -v "${ROOT_DIR}/scripts:/scripts" \
    -e BASE_URL="${docker_base_url}" \
    -e FRONTEND_URL="${FRONTEND_URL:-http://frontend:80}" \
    -e TOPIC="${TOPIC}" \
    -e PLAYER_PREFIX="${PLAYER_PREFIX:-loadtest}" \
    grafana/k6:latest \
    run "$@" "/scripts/${script_file}"
}

ensure_app_running

case "${SCRIPT}" in
  smoke)
    if command -v k6 >/dev/null 2>&1; then
      BASE_URL="${BASE_URL}" TOPIC="${TOPIC}" run_with_k6 smoke.js
    elif [[ "${BASE_URL}" != http://localhost:* ]]; then
      echo "Install k6 for remote endpoint testing: brew install k6"
      echo "Or use: APP_URL=${BASE_URL} ./run-live.sh smoke"
      exit 1
    else
      echo "k6 not installed locally; running via Docker..."
      run_with_docker smoke.js
    fi
    ;;
  load)
    if command -v k6 >/dev/null 2>&1; then
      BASE_URL="${BASE_URL}" TOPIC="${TOPIC}" run_with_k6 quiz-load.js
    else
      run_with_docker quiz-load.js
    fi
    ;;
  stress)
    if command -v k6 >/dev/null 2>&1; then
      BASE_URL="${BASE_URL}" TOPIC="${TOPIC}" run_with_k6 quiz-stress.js
    else
      run_with_docker quiz-stress.js
    fi
    ;;
  frontend)
    if command -v k6 >/dev/null 2>&1; then
      FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}" run_with_k6 frontend-load.js
    else
      FRONTEND_URL="${FRONTEND_URL:-http://frontend:80}" run_with_docker frontend-load.js
    fi
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown script: ${SCRIPT}"
    usage
    exit 1
    ;;
esac
