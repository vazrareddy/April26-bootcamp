# Load Testing — DevOps Dojo Quiz App

This folder contains [k6](https://k6.io) scripts to load-test the quiz API and (optionally) the frontend proxy.

For intentionally triggering CloudWatch alarms, see [`../docs/cloudwatch-alarm-drill.md`](../docs/cloudwatch-alarm-drill.md).

## What gets tested

| Script | Purpose | Load profile |
|--------|---------|--------------|
| `scripts/smoke.js` | Sanity check — 1 user, full quiz journey | 1 iteration |
| `scripts/quiz-load.js` | Normal load — ramp to 25 users | ~5 minutes |
| `scripts/quiz-stress.js` | Stress test — ramp to 100 users | ~9 minutes |
| `scripts/frontend-load.js` | Frontend + proxied `/api` routes | 10 users, 2 minutes |

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

This ramps from 0 → 10 → 25 virtual users over ~5 minutes.

**Default thresholds:**

- Error rate &lt; 2%
- p95 latency &lt; 1500 ms (submit p95 &lt; 1200 ms)

---

## Step 4 — Run stress test (optional)

Find the breaking point:

```bash
./run-local.sh stress
```

Ramps up to **100 concurrent users**. Use only against local compose or a dedicated test environment — not production during class hours.

---

## Step 5 — Test through the frontend proxy (optional)

```bash
./run-local.sh frontend
```

Or:

```bash
k6 run -e FRONTEND_URL=http://localhost:3000 scripts/frontend-load.js
```

This hits the Express server on port 3000, which proxies `/api/*` to the backend.

---

## Step 6 — Watch metrics during the test

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

# 2. Normal load (~25 users, ~5 min)
./run-live.sh load
```

Different topic or URL:

```bash
APP_URL=https://devopsdojo.livingdevops.org TOPIC=kubernetes ./run-live.sh load
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
- Use `smoke` → `load` first; avoid `stress` on a shared dev environment unless intentional

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_URL` | `http://localhost:8000` | API base URL (use live app URL for ECS) |
| `APP_URL` | `https://devopsdojo.livingdevops.org` | Live app URL (`run-live.sh` only) |
| `FRONTEND_URL` | `http://localhost:3000` | Frontend base URL |
| `TOPIC` | `docker` | Quiz topic slug |
| `PLAYER_PREFIX` | `loadtest` | Prefix for generated player names |

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
2. **Load** — baseline at 25 users (`./run-local.sh load`)
3. **Review** — CloudWatch + RDS connections
4. **Stress** — find limits (`./run-local.sh stress`)
5. **Tune** — ECS CPU/memory, RDS size, gunicorn workers, DB pool settings

---

## File layout

```
loadtest/
├── README.md
├── run-local.sh
├── run-live.sh
└── scripts/
    ├── helpers.js        # shared quiz journey logic
    ├── smoke.js          # 1-user sanity test
    ├── quiz-load.js      # normal load profile
    ├── quiz-stress.js    # high load profile
    └── frontend-load.js  # ALB/frontend path test
```
