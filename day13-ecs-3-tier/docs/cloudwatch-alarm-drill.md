# Troubleshooting Scenarios — ECS 3-Tier Quiz App

Interview-style troubleshooting scenarios based on the **day13-ecs-3-tier** stack: React frontend on ECS, Flask backend on ECS (Service Connect), PostgreSQL on RDS, ALB in front, CloudWatch alarms in `infra/cloudwatch.tf`.

Use this doc two ways:

1. **Interview prep** — read the question, try to answer, then check the model answer
2. **Hands-on lab** — simulate each scenario on dev and watch alarms fire (see [Lab appendix](#lab-appendix-simulate-on-dev))

---

## Stack context (know this first)

```
Users → ALB (public) → Frontend ECS task (private)
                              ↓ Service Connect (backend:8000)
                         Backend ECS task (private)
                              ↓ port 5432
                         RDS PostgreSQL (private)
```

| Layer | What runs | Health check |
|-------|-----------|--------------|
| ALB | Routes to frontend only | `GET /health` on frontend |
| Frontend | Express + React static | `/health` → 200 |
| Backend | Flask + gunicorn | `/health` → DB `SELECT 1` |
| RDS | PostgreSQL | N/A (backend checks it) |

**Observability in this project:**

- CloudWatch Logs via `awslogs` on ECS tasks
- EMF metrics from Flask (`RequestDuration`, `HealthCheckFailure`)
- Log metric filters for 5xx and ERROR lines
- 8 CloudWatch alarms in `infra/cloudwatch.tf`
- **No ECS autoscaling** configured — fixed task count under load

**Dev environment names:**

| Item | Value |
|------|--------|
| Live URL | `https://devopsdojo.livingdevops.org` |
| Alarm prefix | `dev-devopsdojo-*` |
| ECS cluster | `dev-april26bootcamp-devopsdojo` |

---

## Scenario 1: Users report the app is down — site returns 503

### The interview question

> *"Users hit your app URL and get 503 Service Unavailable. The ALB is up. Where do you start?"*

### Symptoms

- Browser shows **503**
- `curl -I https://devopsdojo.livingdevops.org/health` → `503`
- ALB is **active**; issue is at the target layer

### How you investigate

1. **ALB → Target groups** — are any targets **healthy**?
2. **ECS → frontend service** — is `runningCount == desiredCount`?
3. **ECS task logs** — is the frontend container crashing on startup?
4. **Target group health check** — path `/health`, expect **200** (not 302)

### Root causes (most common first)

| Cause | Clue |
|-------|------|
| Frontend desired count = 0 | No tasks registered with target group |
| Frontend task failing health check | Tasks start then go **unhealthy** |
| Wrong health check path | ALB expects 200; app redirects or returns 404 |
| Deployment in progress / bad image | New tasks fail; old tasks already drained |

### Fix

- Scale frontend **desired count ≥ 1**
- Fix health check path or app `/health` handler
- Roll back bad deployment if new tasks fail

### Prevention

- Alarm on `UnHealthyHostCount > 0` (we have `dev-devopsdojo-alb-unhealthy-targets`)
- Deployment circuit breaker on ECS
- Smoke test `/health` after every deploy

### CloudWatch alarms

| Alarm | Fires when |
|-------|------------|
| `dev-devopsdojo-alb-unhealthy-targets` | Any unhealthy frontend target |

### Strong interview answer (one paragraph)

*"503 from an ALB almost always means no healthy targets in the target group — not that the ALB itself is broken. I'd check target health first, then ECS frontend service running count vs desired, then task logs for crash loops. Health check misconfiguration is a common gotcha: our frontend must return 200 on `/health`. I'd have an alarm on UnHealthyHostCount so we know before users tell us."*

### Simulate on dev

ECS → frontend service → set **Desired tasks: 0** → wait ~2 min → confirm 503 → scale back to 1.

---

## Scenario 2: Site loads but API calls fail — partial outage

### The interview question

> *"The homepage loads fine but quiz and API calls fail with 502/504/500. Frontend is healthy in the target group. What happened?"*

### Symptoms

- `GET /` works (static React)
- `GET /api/topics` fails
- Frontend logs show **proxy errors** to `http://backend:8000`
- ALB may show rising **HTTPCode_Target_5XX_Count**

### How you investigate

1. Confirm frontend targets are **healthy** (ALB)
2. **ECS → backend service** — running vs desired count
3. **Service Connect** — is backend registered in the mesh namespace?
4. From frontend task network (or Service Connect DNS): can you reach `http://backend:8000/health`?
5. **Backend security group** — allows inbound from frontend SG on port 8000?

### Root causes

| Cause | Clue |
|-------|------|
| Backend scaled to 0 or tasks crashing | `runningCount = 0` |
| Service Connect misconfigured | Frontend cannot resolve `backend:8000` |
| Backend SG blocks frontend | Connection timeout in proxy logs |
| Backend OOM / crash under load | Tasks cycling in ECS events |

### Fix

- Restore backend desired count
- Fix SG rules: frontend SG → backend SG on 8000
- Verify Service Connect namespace and port name match Terraform
- Increase task memory if OOM

### Prevention

- Separate alarms for frontend health vs backend errors
- Monitor `HTTPCode_Target_5XX_Count` on ALB
- Backend `/health` with DB check (we have this)

### CloudWatch alarms

| Alarm | Fires when |
|-------|------------|
| `dev-devopsdojo-alb-target-5xx` | ≥ 10 target 5xx in 5 min |
| `dev-devopsdojo-backend-5xx-rate` | ≥ 5 logged backend 5xx in 5 min |

### Strong interview answer

*"This is a partial outage — edge is fine, API tier is not. Frontend proxies `/api` to the backend over Service Connect, so I'd verify backend tasks are running, then network path: frontend SG to backend SG, then Service Connect DNS. A healthy ALB target doesn't mean the full stack is healthy. I'd alert on target 5xx separately from unhealthy targets."*

### Simulate on dev

Keep frontend at 1, set **backend desired = 0**, run `PLAYER_PREFIX=alarmtest ./run-live.sh load` from `loadtest/`.

---

## Scenario 3: RDS security group is broken — database unreachable

### The interview question

> *"After a security group change, the app is slow or failing. Backend health check fails. RDS looks fine in the console. What do you check?"*

### Symptoms

- Backend `/health` returns **503** with `"database": "disconnected"`
- Quiz API returns 500
- RDS instance status = **available** (misleading — network path is broken)
- CloudWatch: `HealthCheckFailure` metric spikes

### How you investigate

1. **Backend logs** — `"health check failed"` after `SELECT 1`
2. **RDS security group inbound** — is **5432** allowed from **backend SG**?
3. **Backend SG outbound** — can it reach RDS on 5432? (usually allow all outbound)
4. **Subnet routing** — backend and RDS in same VPC private subnets?
5. **Secrets / env** — `DB_HOST`, credentials still correct? (secondary if SG is the issue)

### Root causes

| Cause | Clue |
|-------|------|
| RDS SG rule removed | SG change ticket correlates with incident |
| Wrong source SG on RDS rule | Rule exists but points to old SG |
| RDS moved to new SG without updating rules | Terraform drift or manual change |
| NACL blocking 5432 | Less common; SG is first suspect |

### Fix

- Restore inbound on RDS SG: **PostgreSQL 5432 from backend SG**
- Apply Terraform if SG is managed there: `infra/sg.tf`

### Prevention

- Alarm on `HealthCheckFailure` (`dev-devopsdojo-backend-health-failure`)
- Deep health check that hits DB (not just "process is running")
- Treat SG changes as high-risk; require plan/apply review

### CloudWatch alarms

| Alarm | Fires when |
|-------|------------|
| `dev-devopsdojo-backend-health-failure` | DB health check fails (even once per minute) |
| `dev-devopsdojo-backend-5xx-rate` | Follow-on API errors |

### Strong interview answer

*"RDS can show 'available' while the app cannot connect — that's a network path problem, not a database engine problem. I'd trace backend SG → RDS SG on 5432 first. Our health endpoint runs SELECT 1, so it catches this before users finish a full quiz flow. I'd alarm on that health failure metric, not just on RDS CPU."*

### Simulate on dev

EC2 → RDS security group → **remove inbound rule** for 5432 from backend SG → curl `/health` in a loop → **restore rule** when done.

---

## Scenario 4: Traffic spike — system overloaded, autoscaling not configured

### The interview question

> *"Quiz day — traffic 10x normal. CPU is pegged, responses are slow, some requests fail. You have CloudWatch alarms but no autoscaling. Walk me through what you see and what you'd do."*

### Symptoms

- Page loads slowly; quiz submit times out
- ECS backend **CPU > 80%**, **memory high**
- EMF `RequestDuration` average > 2 seconds
- ALB `TargetResponseTime` > 3 seconds
- Rising 5xx under sustained load
- **Desired count stays at 1** — no new tasks appear

### How you investigate

1. **ECS metrics** — CPU, memory per service
2. **CloudWatch** — `RequestDuration`, `HttpRequestCount` (EMF)
3. **ALB** — request count, latency, 5xx
4. **RDS** — `DatabaseConnections`, CPU (backend pool may exhaust connections)
5. **Check autoscaling** — is there an `aws_appautoscaling_target`? (**Not in this project.**)

### Root causes

| Cause | Clue |
|-------|------|
| Fixed task count, traffic exceeded capacity | CPU/memory alarms, no scale-out events |
| Single backend task bottleneck | One task at 100% CPU |
| DB connection pool exhausted | RDS connections maxed; errors in Flask logs |
| No autoscaling policy | ECS desired count never changes |

### Fix (immediate)

- **Manual scale out** — increase backend `desired_count`
- Stop non-essential traffic if abuse
- **Scale up** task CPU/memory if vertical headroom helps

### Fix (long-term)

- Add **ECS Application Auto Scaling** on CPU or request count
- Tune gunicorn workers vs task CPU
- RDS read replica or larger instance if DB-bound
- Rate limiting on quiz start/submit

### Prevention

| Alarm | Purpose |
|-------|---------|
| `dev-devopsdojo-backend-cpu-high` | Early warning before total failure |
| `dev-devopsdojo-backend-memory-high` | Catch leaks / undersized tasks |
| `dev-devopsdojo-backend-request-latency` | User experience degradation |
| `dev-devopsdojo-alb-high-latency` | End-to-end slowness |

Pair alarms with **auto scaling actions** or runbooks — alarms alone don't fix capacity.

### Strong interview answer

*"Alarms tell you you're on fire; autoscaling is the sprinkler. With fixed desired count, traffic spikes saturate the single Fargate task — CPU and latency alarms fire, then 5xx. I'd scale tasks manually first, then add target-tracking scaling on ECS CPU or ALB request count per target. I'd also check RDS connections because Flask SQLAlchemy pool defaults can become the bottleneck before CPU does."*

### Simulate on dev

```bash
cd day13-ecs-3-tier/loadtest
./run-live.sh load      # ~25 users, ~5 min
./run-live.sh stress    # ~100 users — needed for CPU/memory alarms (~15–20 min)
```

This stack has **no autoscaling** — that's intentional for learning why alarms fire without relief.

---

## Scenario 5: CloudWatch alarm fired — backend 5xx rate high

### The interview question

> *"You get paged for `backend-5xx-rate`. ALB looks mostly fine. How do you find the failing requests?"*

### Symptoms

- Alarm: `dev-devopsdojo-backend-5xx-rate`
- Metric: `Backend5xxCount` from **log metric filter** (`status >= 500` in JSON logs)

### How you investigate

1. **Logs Insights** on `/ecs/dev-april26bootcamp-devopsdojo-backend`:

```
fields @timestamp, method, path, status, duration_ms
| filter status >= 500
| sort @timestamp desc
| limit 50
```

2. Correlate with deploy time, RDS issues, or traffic spike
3. Check **EMF** `RequestDuration` — are slow requests timing out into 5xx?
4. Check recent Terraform / SG / scale changes

### Root causes

Often a **symptom** of Scenarios 2–4, not its own root cause:

- DB unreachable (Scenario 3)
- Backend overloaded (Scenario 4)
- Backend down while frontend proxies (Scenario 2)
- Application bug on specific route

### Fix

Fix the underlying scenario; 5xx alarm clears when errors stop.

### Strong interview answer

*"This alarm is log-driven — it counts structured JSON log lines where status >= 500. I'd use Logs Insights to group by path and status, then correlate with ECS events and RDS health. The alarm tells me customers are getting errors; logs tell me which endpoint and whether it's DB, timeout, or code."*

---

## Scenario 6: Latency alarm — app is slow but not down

### The interview question

> *"Latency alarms fired but error rate is low. Users say the app feels sluggish. What next?"*

### Symptoms

- `dev-devopsdojo-backend-request-latency` — EMF avg > 2000 ms
- `dev-devopsdojo-alb-high-latency` — ALB avg > 3 s
- Error rate still near zero

### How you investigate

1. **Trace the path** — ALB latency vs backend EMF `RequestDuration`
2. **RDS** — slow queries, high CPU, connection wait
3. **ECS CPU** — throttling without hard failures
4. **Downstream** — is frontend waiting on backend on every `/api` call?
5. **Load** — gradual traffic increase without scale-out

### Root causes

- Under-provisioned tasks (Scenario 4, early stage)
- Missing DB index on leaderboard / quiz queries
- Cold start after deploy (less common on Fargate)
- Too few gunicorn workers for CPU allocated

### Fix

- Scale out / up ECS tasks
- Optimize slow DB queries
- Add autoscaling before latency becomes errors

### Strong interview answer

*"Latency alarms are early warnings — users feel pain before 5xx spikes. I'd split ALB latency from backend RequestDuration to see if slowness is proxy, app, or DB. Fix capacity or query performance before error-rate alarms follow."*

---

## Quick reference — symptom → first check

| User report | Check first | Likely scenario |
|-------------|-------------|-----------------|
| 503 on everything | ALB target health | **1** — frontend down |
| UI works, quiz broken | Backend ECS count + Service Connect | **2** — backend down |
| Worked until SG change | RDS SG inbound 5432 | **3** — RDS SG broken |
| Slow then errors under load | ECS CPU + desired count | **4** — overload, no autoscaling |
| Paged on 5xx alarm | Logs Insights by path | **5** — symptom of 2–4 |
| Slow but no errors | EMF latency + RDS | **6** — capacity or DB |

---

## Alarm cheat sheet

| Alarm | What it really means |
|-------|----------------------|
| `alb-unhealthy-targets` | No healthy frontend for ALB |
| `alb-target-5xx` | Users getting server errors through frontend |
| `alb-high-latency` | End-user requests taking > 3 s avg |
| `backend-cpu-high` | Backend task CPU > 80% sustained |
| `backend-memory-high` | Backend task memory > 80% sustained |
| `backend-request-latency` | Flask requests > 2 s avg (EMF) |
| `backend-5xx-rate` | Logged HTTP 5xx count high |
| `backend-health-failure` | Backend cannot reach RDS |

---

## Lab appendix — simulate on dev

**Before each lab:** CloudWatch → Alarms open. Restore after each test.

| Scenario | Break it | Recover |
|----------|----------|---------|
| **1 — 503 / frontend** | Frontend desired = 0 | Frontend desired = 1 |
| **2 — API down** | Backend desired = 0 + `./run-live.sh load` | Backend desired = 1 |
| **3 — RDS SG** | Remove RDS SG inbound from backend | Restore SG rule |
| **4 — Overload** | `./run-live.sh stress` for 15–20 min | Stop k6; wait for metrics |

```bash
# Preflight
curl https://devopsdojo.livingdevops.org/health

# Load tests (Scenarios 2 & 4)
cd day13-ecs-3-tier/loadtest
./run-live.sh smoke
PLAYER_PREFIX=alarmtest ./run-live.sh load
PLAYER_PREFIX=alarmtest ./run-live.sh stress
```

**List alarm states:**

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix dev-devopsdojo \
  --region ap-south-1 \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}' \
  --output table
```

---

## Related files

| File | Purpose |
|------|---------|
| `infra/cloudwatch.tf` | Alarm definitions |
| `infra/sg.tf` | Security groups (Scenario 3) |
| `infra/ecs.tf` | Services, Service Connect |
| `app/backend/app/__init__.py` | DB health check, EMF logging |
| `loadtest/run-live.sh` | Load against live URL |
| `loadtest/README.md` | k6 setup |

---

## Bonus interview questions (short)

**Q: Why is the backend not behind the ALB directly?**  
A: Three-tier design — only frontend is public. Backend stays private; Service Connect gives stable DNS (`backend:8000`) without exposing it to the internet.

**Q: Why use EMF instead of PutMetricData?**  
A: EMF writes metrics through logs we already ship to CloudWatch — no extra IAM permissions or API calls from the app.

**Q: What's missing for production readiness in this stack?**  
A: ECS autoscaling, SNS on alarms, multi-AZ RDS (prod tfvars), rate limiting, and runbooks linked to each alarm.

**Q: How would you know the problem is RDS vs the app?**  
A: Backend `/health` runs `SELECT 1` — fails with DB issues before quiz logic runs. Check `HealthCheckFailure` metric and health response body.
