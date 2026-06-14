# CloudWatch Alarm Drill Guide

Step-by-step guide to **intentionally trigger** each CloudWatch alarm defined in `infra/cloudwatch.tf`, verify it fired, and recover safely.

Use this on the **dev** environment only unless you explicitly own prod.

---

## Environment reference

| Item | Value |
|------|--------|
| Live app URL | `https://devopsdojo.livingdevops.org` |
| Alarm name prefix | `dev-devopsdojo-*` |
| Metric namespace (app) | `dev/devopsdojo/Backend` |
| ECS cluster | `dev-april26bootcamp-devopsdojo` |
| Backend service | `dev-april26bootcamp-devopsdojo-backend` |
| Frontend service | `dev-april26bootcamp-devopsdojo-frontend` |
| Backend log group | `/ecs/dev-april26bootcamp-devopsdojo-backend` |

Replace `dev` / `devopsdojo` if your Terraform vars differ.

---

## Before you start

### 1. Confirm alarms exist

AWS Console → **CloudWatch** → **Alarms** → filter by `dev-devopsdojo`.

You should see 8 alarms:

| Alarm name | Metric |
|------------|--------|
| `dev-devopsdojo-alb-unhealthy-targets` | `UnHealthyHostCount` |
| `dev-devopsdojo-alb-target-5xx` | `HTTPCode_Target_5XX_Count` |
| `dev-devopsdojo-alb-high-latency` | `TargetResponseTime` |
| `dev-devopsdojo-backend-cpu-high` | `CPUUtilization` |
| `dev-devopsdojo-backend-memory-high` | `MemoryUtilization` |
| `dev-devopsdojo-backend-request-latency` | `RequestDuration` (EMF) |
| `dev-devopsdojo-backend-5xx-rate` | `Backend5xxCount` (log filter) |
| `dev-devopsdojo-backend-health-failure` | `HealthCheckFailure` (EMF) |

### 2. Add SNS notifications (required to receive alerts)

Alarms currently change state in CloudWatch but **do not email you** until SNS is wired.

**Terraform sketch** (add to `infra/cloudwatch.tf`):

```hcl
resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-${var.project}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "your-email@example.com"   # change this
}

# On each aws_cloudwatch_metric_alarm:
# alarm_actions = [aws_sns_topic.alerts.arn]
# ok_actions    = [aws_sns_topic.alerts.arn]
```

Then:

```bash
cd infra
terraform apply -var-file=vars/dev.tfvars
```

Confirm the SNS subscription from your inbox before running drills.

### 3. Open these tabs before each drill

- CloudWatch → **Alarms**
- CloudWatch → **Metrics** (relevant namespace)
- ECS → cluster → **Services**
- (Optional) `/ecs/...-backend` log group → **Logs Insights**

### 4. General rules

- Run drills in a **maintenance window** — the live app may return 503 or slow down.
- Alarms use **evaluation periods** — expect **1–15 minutes** before state = `ALARM`.
- After each drill: **recover** → wait for state = `OK` → then start the next drill.
- Load tests add `loadtest_*` names to the live leaderboard — use `PLAYER_PREFIX=alarmtest`.

---

## Quick reference — how to trigger each alarm

| # | Alarm | Easiest trigger | Recovery | Typical wait |
|---|-------|-----------------|----------|--------------|
| 1 | `backend-health-failure` | Block backend → RDS on port 5432 | Restore SG rule | ~1–2 min |
| 2 | `backend-5xx-rate` | Scale backend to 0 + load test | Scale backend to 1 | ~5 min |
| 3 | `backend-request-latency` | Sustained slow API responses | Stop slow traffic | ~3 min |
| 4 | `alb-unhealthy-targets` | Scale frontend to 0 | Scale frontend to 1 | ~2 min |
| 5 | `alb-target-5xx` | Scale backend to 0 + live load test | Scale backend to 1 | ~5–10 min |
| 6 | `alb-high-latency` | Slow responses through live URL | Stop slow traffic | ~3 min |
| 7 | `backend-cpu-high` | `./run-live.sh stress` | Stop k6 | ~15 min |
| 8 | `backend-memory-high` | `./run-live.sh stress` (or memory leak sim) | Stop k6 | ~15 min |

Recommended order: **1 → 4 → 5 → 2 → 3 → 6 → 7/8**

---

## Drill 1 — `backend-health-failure`

**What it means:** Backend `/health` cannot reach RDS (`SELECT 1` fails).  
**Metric:** `HealthCheckFailure` in `dev/devopsdojo/Backend`  
**Threshold:** Sum > 0 in 60 seconds (even one failure fires).

### Trigger

1. AWS Console → **EC2** → **Security Groups**
2. Find the **RDS security group** (allows 5432 from backend SG)
3. **Edit inbound rules** → remove or disable the rule allowing PostgreSQL from the backend SG
4. Generate health check traffic:

```bash
# Hit backend health via frontend proxy (live app)
while true; do
  curl -s -o /dev/null -w "%{http_code}\n" https://devopsdojo.livingdevops.org/health
  sleep 2
done
```

Or call the backend health path if you have VPC access:

```bash
curl -s http://<backend-task-ip>:8000/health
```

### Verify

- CloudWatch alarm `dev-devopsdojo-backend-health-failure` → **ALARM**
- Backend logs contain `"health check failed"` with `"levelname": "ERROR"`
- EMF line with `HealthCheckFailure` in log group

### Recover

1. Restore the RDS inbound rule (backend SG → port 5432)
2. Confirm health returns 200:

```bash
curl https://devopsdojo.livingdevops.org/health
```

3. Wait 1–2 minutes for alarm → **OK**

---

## Drill 2 — `backend-5xx-rate`

**What it means:** ≥ 5 HTTP 5xx responses logged in 5 minutes.  
**Metric:** `Backend5xxCount` (log metric filter on `{ $.status >= 500 }`)

### Trigger (option A — backend down, recommended)

1. ECS → `dev-april26bootcamp-devopsdojo-backend` → **Update service** → **Desired tasks: 0**
2. Wait ~30 seconds for tasks to stop
3. Run load test through live URL (frontend proxy will error):

```bash
cd loadtest
brew install k6   # if needed
PLAYER_PREFIX=alarmtest ./run-live.sh load
```

4. Let it run until alarm fires (~5 minutes of 5xx logs)

### Trigger (option B — repeated real 500s)

If you add a dev-only route that returns 500 (see [Future improvements](#future-improvements)), hit it 6+ times in 5 minutes:

```bash
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{http_code}\n" https://devopsdojo.livingdevops.org/api/debug/500
  sleep 5
done
```

### Verify

- Alarm `dev-devopsdojo-backend-5xx-rate` → **ALARM**
- Logs Insights query:

```
fields @timestamp, status, path, method
| filter status >= 500
| sort @timestamp desc
| limit 20
```

### Recover

1. Scale backend desired tasks back to **1**
2. Stop k6 (Ctrl+C)
3. Wait for 5xx count to drop → alarm **OK**

---

## Drill 3 — `backend-request-latency`

**What it means:** Average `RequestDuration` (EMF) > **2000 ms** for 3 consecutive 60-second periods.  
**Metric:** `RequestDuration` in `dev/devopsdojo/Backend`

### Trigger

You need sustained slow API requests (~3+ minutes).

**Option A — load + slow endpoint (after adding debug route):**

```bash
k6 run -e BASE_URL=https://devopsdojo.livingdevops.org loadtest/scripts/quiz-load.js
# while a /api/debug/slow?s=3 endpoint is enabled on backend
```

**Option B — temporary Flask delay (dev only):**

Add a short sleep in a frequently hit route (e.g. `/api/topics`) behind `FLASK_DEBUG=1`, deploy, then:

```bash
cd loadtest
./run-live.sh load
```

Keep load running for **at least 4 minutes**.

### Verify

- Alarm `dev-devopsdojo-backend-request-latency` → **ALARM**
- CloudWatch → Metrics → `dev/devopsdojo/Backend` → `RequestDuration` graph shows avg > 2000

### Recover

1. Remove sleep / disable slow endpoint
2. Redeploy backend if needed
3. Stop load test

---

## Drill 4 — `alb-unhealthy-targets`

**What it means:** ALB target group has **any** unhealthy frontend task.  
**Metric:** `UnHealthyHostCount` > 0 for 2 × 60-second periods.

### Trigger

**Easiest:** scale frontend to zero.

1. ECS → `dev-april26bootcamp-devopsdojo-frontend` → **Update service** → **Desired tasks: 0**
2. Wait ~2 minutes

Alternative: deploy a broken frontend image where `/health` returns non-200.

### Verify

- Alarm `dev-devopsdojo-alb-unhealthy-targets` → **ALARM**
- EC2 → **Target Groups** → targets show **unhealthy**
- Live URL returns **503**:

```bash
curl -I https://devopsdojo.livingdevops.org/health
```

### Recover

1. Scale frontend desired tasks to **1**
2. Wait for target **healthy** (~1–2 min)
3. Alarm → **OK**

---

## Drill 5 — `alb-target-5xx`

**What it means:** ≥ **10** HTTP 5xx from targets in a **5-minute** window (2 evaluation periods).  
**Metric:** `HTTPCode_Target_5XX_Count`

### Trigger

1. Keep **frontend** at desired = 1
2. Scale **backend** to desired = 0
3. Run live load test:

```bash
cd loadtest
PLAYER_PREFIX=alarmtest ./run-live.sh load
```

Frontend proxy errors produce target 5xx visible to the ALB.

### Verify

- Alarm `dev-devopsdojo-alb-target-5xx` → **ALARM**
- ALB metrics → `HTTPCode_Target_5XX_Count` rising

### Recover

1. Scale backend to **1**
2. Stop k6
3. Wait ~5–10 minutes for metric to clear

---

## Drill 6 — `alb-high-latency`

**What it means:** ALB `TargetResponseTime` average > **3 seconds** for 3 × 60-second periods.

### Trigger

Same as Drill 3, but traffic must go through the **live URL** (not direct backend):

```bash
cd loadtest
./run-live.sh load
```

Requires backend responses (or proxy) consistently > 3s — use a dev slow endpoint or artificial delay.

### Verify

- Alarm `dev-devopsdojo-alb-high-latency` → **ALARM**
- ALB metric `TargetResponseTime` > 3

### Recover

Remove delay, stop load, wait ~3 minutes.

---

## Drill 7 — `backend-cpu-high`

**What it means:** Backend ECS service CPU > **80%** average for 3 × **5-minute** periods (~15 min).

### Trigger

```bash
cd loadtest
brew install k6
./run-live.sh stress
```

Let it run **at least 20 minutes**. If CPU stays below 80% on 1024 CPU Fargate:

- Run stress + normal load together, or
- Temporarily lower task CPU in Terraform (e.g. 256) so the same load hits a higher %

### Verify

- ECS → backend service → **Metrics** → CPU > 80%
- Alarm `dev-devopsdojo-backend-cpu-high` → **ALARM**

### Recover

Stop k6; CPU alarm clears after ~15 minutes of normal utilization.

---

## Drill 8 — `backend-memory-high`

**What it means:** Backend memory > **80%** for 3 × 5-minute periods.

### Trigger

Same as Drill 7 — stress load is the first approach. Memory alarms often need:

- Longer stress duration, or
- A dev endpoint that allocates memory (advanced)

### Verify

- ECS → backend → Memory utilization > 80%
- Alarm `dev-devopsdojo-backend-memory-high` → **ALARM**

### Recover

Stop stress load; restart tasks if needed (ECS → **Force new deployment**).

---

## Verification checklist (use for every drill)

Copy this per alarm:

```
[ ] Alarm name: _______________________
[ ] Trigger action completed
[ ] CloudWatch alarm state = ALARM (time: ___)
[ ] SNS email received (if configured)
[ ] Metric graph shows expected spike
[ ] Recovery action completed
[ ] Alarm state = OK (time: ___)
[ ] Live app healthy (curl /health = 200)
```

**Live health check:**

```bash
curl -s https://devopsdojo.livingdevops.org/health
curl -s https://devopsdojo.livingdevops.org/api/topics | head -c 200
```

---

## Useful AWS CLI commands

List alarms:

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "dev-devopsdojo" \
  --region ap-south-1 \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}' \
  --output table
```

Watch alarm state:

```bash
watch -n 10 'aws cloudwatch describe-alarms \
  --alarm-names dev-devopsdojo-backend-health-failure \
  --region ap-south-1 \
  --query "MetricAlarms[0].StateValue" \
  --output text'
```

Scale ECS service:

```bash
aws ecs update-service \
  --cluster dev-april26bootcamp-devopsdojo \
  --service dev-april26bootcamp-devopsdojo-backend \
  --desired-count 0 \
  --region ap-south-1
```

Restore:

```bash
aws ecs update-service \
  --cluster dev-april26bootcamp-devopsdojo \
  --service dev-april26bootcamp-devopsdojo-backend \
  --desired-count 1 \
  --region ap-south-1
```

Logs Insights (backend 5xx):

```bash
aws logs start-query \
  --log-group-name "/ecs/dev-april26bootcamp-devopsdojo-backend" \
  --start-time $(($(date +%s) - 900)) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, status, path | filter status >= 500 | sort @timestamp desc | limit 20' \
  --region ap-south-1
```

---

## Load test commands (live app)

From `day13-ecs-3-tier/loadtest`:

```bash
# Preflight
curl https://devopsdojo.livingdevops.org/health

# Light traffic
./run-live.sh smoke

# Sustained load (5xx, latency drills)
PLAYER_PREFIX=alarmtest ./run-live.sh load

# Heavy load (CPU / memory drills)
PLAYER_PREFIX=alarmtest ./run-live.sh stress
```

See `loadtest/README.md` for full details.

---

## Future improvements

For repeatable drills without scaling services to zero, add **dev-only** routes (gated by env var `ENABLE_ALARM_TEST_ROUTES=1`):

| Route | Alarm triggered |
|-------|-----------------|
| `GET /api/debug/500` | `backend-5xx-rate` |
| `GET /api/debug/slow?s=3` | `backend-request-latency`, `alb-high-latency` |
| `GET /api/debug/health-fail` | `backend-health-failure` (mock EMF, no RDS break) |

Plus a k6 script `loadtest/scripts/alarm-drill.js` that runs each scenario in sequence.

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Alarm stays OK | Not enough signal / wrong period | Wait full evaluation window; check metric graph |
| Alarm stuck ALARM | Metric still breaching | Complete recovery; check ECS tasks running |
| No email | SNS not configured | Add SNS + `alarm_actions` in Terraform |
| 503 on live URL | Frontend scaled to 0 or unhealthy | Scale frontend to 1; check target group |
| Load test fails immediately | Live app down | Fix ECS services first |
| `backend-5xx-rate` never fires | Errors not logged as `status >= 500` | Confirm JSON logs include numeric `status` field |

---

## Related files

| File | Purpose |
|------|---------|
| `infra/cloudwatch.tf` | Alarm definitions + log metric filters |
| `app/backend/app/cloudwatch_metrics.py` | EMF metrics (`RequestDuration`, `HealthCheckFailure`) |
| `app/backend/app/logging_config.py` | JSON logs for 5xx filter |
| `loadtest/run-live.sh` | Load test against live URL |
| `loadtest/README.md` | Load testing guide |
