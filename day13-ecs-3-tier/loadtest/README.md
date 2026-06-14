# Load Testing — DevOps Dojo Quiz App

This folder contains [k6](https://k6.io) scripts to load-test the quiz API and (optionally) the frontend proxy.

For intentionally triggering CloudWatch alarms, see [`../docs/cloudwatch-alarm-drill.md`](../docs/cloudwatch-alarm-drill.md).

## What gets tested

| Script | Purpose | Load profile |
|--------|---------|--------------|
| `scripts/smoke.js` | Sanity check — 1 user, full quiz journey | 1 iteration |
| `scripts/quiz-load.js` | Normal load — ramp to 50 users | ~5 minutes |
| `scripts/quiz-constant.js` | Constant load — separate VU pool per API route | 10 minutes (default) |
| `scripts/quiz-stress.js` | Stress test — ramp to 200 users | ~9 minutes |
| `scripts/frontend-load.js` | Frontend + proxied `/api` routes | 20 users, 2 minutes |

Each quiz journey simulates a real user:

1. `GET /health`
2. `GET /api/topics`
3. `POST /api/quiz/:topic/start`
4. `POST /api/quiz/submit`
5. `GET /api/leaderboard?scope=topic&topic=...`
6. `GET /api/leaderboard/stats`

---

## Prerequisites

Choose **one** way to run k6:

### Option A — Install k6 locally (recommended)

```bash
# macOS
brew install k6

# Linux (Debian/Ubuntu)
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6
```

### Option B — Run k6 via Docker (no install)

Uses the `grafana/k6` image on the compose network (`app_default`). When using Docker, `run-local.sh` automatically targets `http://backend:8000` instead of `localhost`.

---

## Step 1 — Start the app

From the repo root:

```bash
cd day13-ecs-3-tier/app
docker compose up --build -d
```

Wait until the backend is healthy:

```bash
curl http://localhost:8000/health
```

Expected:

```json
{"status":"healthy","database":"connected"}
```

App URLs:

| Service | URL |
|---------|-----|
| Frontend | http://localhost:3000 |
| Backend API | http://localhost:8000 |

---

## Step 2 — Run smoke test

From `day13-ecs-3-tier/loadtest`:

```bash
chmod +x run-local.sh
./run-local.sh smoke
```

Or directly with k6:

```bash
k6 run scripts/smoke.js
```

With custom topic (must exist in the database):

```bash
k6 run -e BASE_URL=http://localhost:8000 -e TOPIC=kubernetes scripts/smoke.js
```

**Pass criteria:** 0% failed requests, all checks green.

---

## Step 3 — Run load test

```bash
./run-local.sh load
```

Or:

```bash
k6 run scripts/quiz-load.js
```

This ramps from 0 → 20 → 50 virtual users over ~5 minutes.

**Default thresholds:**

- Error rate &lt; 2%
- p95 latency &lt; 1500 ms (submit p95 &lt; 1200 ms)

---

## Step 4 — Run constant load (per request type)

`quiz-constant.js` runs **five parallel scenarios**, each hammering one API route with a steady VU count for a fixed duration.

| Scenario | Endpoint |
|----------|----------|
| `quiz_start` | `POST /api/quiz/:topic/start` |
| `quiz_submit` | `POST /api/quiz/submit` |
| `leaderboard_topic` | `GET /api/leaderboard?scope=topic&topic=...` |
| `leaderboard_stats` | `GET /api/leaderboard/stats` |
| `topics` | `GET /api/topics` |

**Defaults:** 50 VUs per scenario, 10 minute duration (250 total concurrent VUs).

### Local

```bash
# Default: 50 VUs per route, 10 minutes
./run-local.sh constant

# Custom duration and global VU count
VUS=30 DURATION=5m k6 run -e BASE_URL=http://localhost:8000 scripts/quiz-constant.js

# Tune each request type independently
VUS_START=40 VUS_SUBMIT=60 VUS_LEADERBOARD=30 VUS_STATS=30 VUS_TOPICS=20 DURATION=10m \
  k6 run -e BASE_URL=http://localhost:8000 scripts/quiz-constant.js
```

### Live

```bash
# Default constant load against production
./run-live.sh constant

# 10 minutes at 50 VUs per route
VUS=50 DURATION=10m ./run-live.sh constant

# Heavier submit load, lighter reads
VUS=50 VUS_SUBMIT=100 VUS_STATS=25 VUS_TOPICS=25 DURATION=10m ./run-live.sh constant

# Different topic
TOPIC=kubernetes VUS=40 DURATION=10m ./run-live.sh constant
```

### Direct k6 (any target)

```bash
k6 run \
  -e BASE_URL=https://devopsdojo.livingdevops.org \
  -e TOPIC=docker \
  -e VUS=50 \
  -e DURATION=10m \
  -e VUS_START=50 \
  -e VUS_SUBMIT=50 \
  -e VUS_LEADERBOARD=50 \
  -e VUS_STATS=50 \
  -e VUS_TOPICS=50 \
  scripts/quiz-constant.js
```

---

## Step 5 — Run stress test (optional)

Find the breaking point:

```bash
./run-local.sh stress
```

Ramps up to **200 concurrent users**. Use only against local compose or a dedicated test environment — not production during class hours.

---

## Step 6 — Test through the frontend proxy (optional)

```bash
./run-local.sh frontend
```

Or:

```bash
k6 run -e FRONTEND_URL=http://localhost:3000 scripts/frontend-load.js
```

This hits the Express server on port 3000, which proxies `/api/*` to the backend.

---

## Step 7 — Watch metrics during the test

### k6 terminal output

Watch for:

- `http_req_failed` — should stay near 0%
- `http_req_duration` p95 / p99
- `checks` — pass rate should be 100%

### CloudWatch (ECS deployment)

While the test runs against AWS, open CloudWatch and monitor:

| Metric | Where |
|--------|--------|
| `RequestDuration`, `HttpRequestCount` | `{env}/devopsdojo/Backend` namespace (EMF) |
| `Backend5xxCount` | Log metric filter / custom namespace |
| `TargetResponseTime`, `HTTPCode_Target_5XX_Count` | `AWS/ApplicationELB` |
| `CPUUtilization`, `MemoryUtilization` | `AWS/ECS` (backend service) |
| `DatabaseConnections` | `AWS/RDS` |

### Local logs

```bash
cd ../app
docker compose logs -f backend
```

---

## Load testing the LIVE app (ECS / ALB)

The backend is **not public**. All traffic must go through the frontend URL — it proxies `/api/*` to the backend via Service Connect.

**Default live URL:** `https://devopsdojo.livingdevops.org`

### Install k6 (required for live)

```bash
brew install k6
```

### Run against live

```bash
cd day13-ecs-3-tier/loadtest
chmod +x run-live.sh

# 1. Sanity check (always first)
./run-live.sh smoke

# 2. Normal ramping load (~50 users peak, ~5 min)
./run-live.sh load

# 3. Constant load — 50 VUs per route, 10 min (default)
./run-live.sh constant

# 4. Constant load with custom VU variables
VUS=50 DURATION=10m ./run-live.sh constant
VUS_SUBMIT=80 VUS_STATS=40 DURATION=15m ./run-live.sh constant
```

Different topic or URL:

```bash
APP_URL=https://devopsdojo.livingdevops.org TOPIC=kubernetes ./run-live.sh load
VUS=25 DURATION=5m TOPIC=kubernetes ./run-live.sh constant
```

Or directly with k6:

```bash
k6 run -e BASE_URL=https://devopsdojo.livingdevops.org -e TOPIC=docker scripts/smoke.js
```

### Preflight checks

```bash
curl https://devopsdojo.livingdevops.org/health
curl https://devopsdojo.livingdevops.org/api/topics
```

### Live test notes

- Quiz traffic hits `{APP_URL}/api/quiz/...` through the ALB → frontend → backend path
- Player names `loadtest_vu*_iter*` will appear on the **live leaderboard**
- Watch CloudWatch alarms while the test runs (5xx, latency, ECS CPU, RDS connections)
- Use `smoke` → `load` → `constant` first; avoid `stress` on a shared dev environment unless intentional

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_URL` | `http://localhost:8000` | API base URL (use live app URL for ECS) |
| `APP_URL` | `https://devopsdojo.livingdevops.org` | Live app URL (`run-live.sh` only) |
| `FRONTEND_URL` | `http://localhost:3000` | Frontend base URL |
| `TOPIC` | `docker` | Quiz topic slug |
| `PLAYER_PREFIX` | `loadtest` | Prefix for generated player names |
| `VUS` | `50` | Default VUs **per scenario** in `quiz-constant.js` |
| `VUS_START` | `VUS` | VUs for `POST /api/quiz/:topic/start` |
| `VUS_SUBMIT` | `VUS` | VUs for `POST /api/quiz/submit` |
| `VUS_LEADERBOARD` | `VUS` | VUs for `GET /api/leaderboard` |
| `VUS_STATS` | `VUS` | VUs for `GET /api/leaderboard/stats` |
| `VUS_TOPICS` | `VUS` | VUs for `GET /api/topics` |
| `DURATION` | `10m` | Constant-load duration (k6 format, e.g. `5m`, `30s`) |

### Quick reference — VU variable commands

```bash
# Same VUs for every route
VUS=50 DURATION=10m ./run-live.sh constant

# Only increase submit pressure
VUS=50 VUS_SUBMIT=100 ./run-live.sh constant

# Light read load, heavy write load
VUS_START=60 VUS_SUBMIT=80 VUS_LEADERBOARD=20 VUS_STATS=20 VUS_TOPICS=20 DURATION=10m ./run-live.sh constant

# Local with k6 directly
VUS=25 DURATION=5m k6 run -e BASE_URL=http://localhost:8000 scripts/quiz-constant.js
```

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|--------------|-----|
| Connection refused | App not running | `docker compose up -d` in `app/` |
| `start status 404` | Topic has no questions | Seed data or upload questions for that topic |
| High submit failures | DB connection pool exhausted | Reduce VUs or scale ECS tasks / RDS |
| `409` on submit | Reusing same session | Expected if script submits twice — our scripts create a new session each iteration |
| Docker k6 network error | Wrong compose network | Ensure compose project is named `app` (`app_default` network) or pass `--network` explicitly |

Check available topics:

```bash
curl http://localhost:8000/api/topics
```

---

## Suggested test progression

1. **Smoke** — confirm scripts work (`./run-local.sh smoke`)
2. **Load** — baseline ramp to 50 users (`./run-local.sh load`)
3. **Constant** — steady per-route load (`VUS=50 DURATION=10m ./run-live.sh constant`)
4. **Review** — CloudWatch + RDS connections
5. **Stress** — find limits (`./run-live.sh stress`)
6. **Tune** — ECS CPU/memory, RDS size, gunicorn workers, DB pool settings

---

## File layout

```
loadtest/
├── README.md
├── run-local.sh
├── run-live.sh
└── scripts/
    ├── helpers.js        # shared request helpers per route
    ├── smoke.js          # 1-user sanity test
    ├── quiz-load.js      # ramping load profile
    ├── quiz-constant.js  # constant VUs per API route
    ├── quiz-stress.js    # high load profile
    └── frontend-load.js  # ALB/frontend path test
```
