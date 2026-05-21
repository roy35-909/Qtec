# Production-Style API Deployment with Docker, Nginx, CI/CD & Monitoring

A small but complete production-style system built for a DevOps engineering task. It exposes a REST API behind a reverse proxy, runs across multiple containers, ships with a CI/CD pipeline, and includes live monitoring through Prometheus and Grafana.

---

## Table of Contents

- [System Architecture](#system-architecture)
- [Tech Stack](#tech-stack)
- [The API](#the-api)
- [Containerization](#containerization)
- [Reverse Proxy & Load Balancing](#reverse-proxy--load-balancing)
- [CI/CD Pipeline](#cicd-pipeline)
- [Monitoring & Logs](#monitoring--logs)
- [How ~100 req/sec is handled](#how-100-reqsec-is-handled)
- [Zero-Downtime Deployment](#zero-downtime-deployment)
- [Running Locally](#running-locally)
- [Screenshots](#screenshots)

---

## System Architecture

```
User
 │
 ▼
Nginx (port 80)          ← reverse proxy, load balancer
 │
 ├──▶ app1:8000          ← FastAPI container (worker 1)
 ├──▶ app2:8000          ← FastAPI container (worker 2)
 └──▶ app3:8000          ← FastAPI container (worker 3)
          │
          ▼
    Prometheus            ← scrapes /metrics from all 3 containers
          │
          ▼
      Grafana             ← visualizes request rate, latency, error rate, uptime
```

GitHub Actions handles CI/CD — on every push to `main`, it runs tests, builds the Docker image, and deploys to the server using a rolling update strategy.

---

## Tech Stack

| Layer | Tool |
|---|---|
| API | Python, FastAPI, Uvicorn |
| Containerization | Docker, Docker Compose |
| Reverse proxy | Nginx |
| CI/CD | GitHub Actions |
| Metrics | Prometheus, prometheus-fastapi-instrumentator |
| Dashboards | Grafana |
| Load testing | hey |

---

## The API

Two endpoints:

### `GET /status`

Returns a health check with current server time.

```bash
curl http://localhost/status
```

```json
{
  "status": "ok",
  "timestamp": 1716291600.123
}
```

### `POST /data`

Accepts a JSON payload and echoes it back.

```bash
curl -X POST http://localhost/data \
  -H "Content-Type: application/json" \
  -d '{"key": "environment", "value": "production"}'
```

```json
{
  "received": true,
  "key": "environment"
}
```

Both endpoints are instrumented — every request is tracked automatically by Prometheus via the `/metrics` endpoint on each container.

---

## Containerization

The app is packaged with a production-style Dockerfile:

- Based on `python:3.12-slim` to keep the image small
- Runs as a **non-root user** (`appuser`) — no root privileges inside the container
- Uvicorn starts with **4 worker processes** per container
- All configuration (port, env) comes from environment variables — no hardcoded values
- Dependencies installed from `requirements.txt` with `--no-cache-dir` to avoid bloating the layer

```bash
# Build and run manually
docker build -t fastapi-app .
docker run -p 8000:8000 --env PORT=8000 fastapi-app
```

Or use Compose to bring up the full stack:

```bash
docker compose up -d
```

---

## Reverse Proxy & Load Balancing

Nginx sits in front of all three app containers. It uses the `least_conn` strategy — new requests go to whichever container currently has the fewest active connections. This works better than round-robin when some requests take longer than others.

```nginx
upstream app_backend {
    least_conn;
    server app1:8000;
    server app2:8000;
    server app3:8000;
}
```

Nginx also handles:

- Request logging (`access.log`)
- Proxy headers forwarding (`X-Real-IP`, `Host`)
- Connection timeouts (5s connect, 30s read)

All traffic goes through port 80. The app containers are not exposed directly.

---

## CI/CD Pipeline
The CI/CD workflow is defined in [.github/workflows/deploy.yml](.github/workflows/deploy.yml#L1-L200) and runs on every push to the `main` branch.

**Overview**
- **Runner actions:** The workflow uses `actions/checkout@v4` (checkout source on the runner) and `actions/setup-python@v5` for the test step.
- **Image lifecycle:** The runner builds a Docker image from `app/`, tags it with the commit SHA, and pushes it to the configured Docker registry.
- **Deployment:** The final step SSHs into the server and performs a rolling update by pulling the pushed image and restarting containers one at a time.

**Stages (detailed)**
- **Test**: runs on `ubuntu-latest` and executes:
  - `actions/checkout@v4`
  - `actions/setup-python@v5` (Python 3.12)
  - `pip install -r app/requirements.txt`
  - `pytest tests/`
- **Build**: builds the Docker image inside the `app/` folder and tags it as `myapp:${{ github.sha }}`.
- **Push**: logs into the Docker registry using `secrets.DOCKER_USERNAME` and `secrets.DOCKER_PASSWORD`, tags the image for the registry, and pushes it.
- **Deploy**: connects via SSH (using `appleboy/ssh-action@v1`) to the server and runs `docker compose pull` followed by rolling `docker compose up -d --no-deps <service>` commands to achieve zero-downtime updates.

**Important files**
- Workflow: [.github/workflows/deploy.yml](.github/workflows/deploy.yml#L1-L200)
- Compose: [docker-compose.yml](docker-compose.yml#L1-L200)

**Secrets required**
- `DOCKER_USERNAME` — Docker registry username
- `DOCKER_PASSWORD` — Docker registry password (used with `docker login`)
- `SERVER_HOST` — target server IP/hostname for SSH deploy
- `SERVER_USER` — SSH user
- `SSH_PRIVATE_KEY` — private key used by the `appleboy/ssh-action` to authenticate

Keep secrets in the repository's Settings → Secrets and ensure they are scoped to the repository.

**How deployment works (notes for operators)**
- The workflow pushes the image to the registry; the remote host must have the Compose YAML(s) that reference the published image (or use the `IMAGE_TAG` environment variable in those compose files).
- The deploy step does **not** require the server to have a git checkout. Instead it runs `docker compose pull` and `docker compose up -d --no-deps` for a rolling update.

**If you prefer to sync source files instead**
You can copy the checked-out repository from the runner to the server instead of relying on the registry. Example using `appleboy/scp-action`:

```yaml
- name: Copy files to server
  uses: appleboy/scp-action@v0.1.3
  with:
    host: ${{ secrets.SERVER_HOST }}
    username: ${{ secrets.SERVER_USER }}
    key: ${{ secrets.SSH_PRIVATE_KEY }}
    source: "./"
    target: "/opt/myapp"
```

After copying, you can SSH in and run `docker compose up -d --build` on the server to build from the copied source.

**Security & best practices**
- Do not store private keys or passwords in the repository. Use GitHub Actions secrets.
- Limit the scope of the SSH user on the server (use a deploy-specific user with minimal privileges).
- Prefer deploying from pre-built, signed images for reproducibility and faster deploys.

**Quick troubleshooting**
- If the deploy fails to pull the image, verify the image tag and registry permissions.
- Check `docker compose ps` and `docker compose logs` on the server for container-level failures.

**Screenshots (placeholders)**
<img width="825" height="458" alt="Screenshot from 2026-05-21 20-49-35" src="https://github.com/user-attachments/assets/3dcc357e-c2cd-4d95-b0ca-9861ebb11ee8" />

<img width="1459" height="562" alt="Screenshot from 2026-05-21 20-47-06" src="https://github.com/user-attachments/assets/3f0e9bea-ef34-42ea-aa2d-24354b3f5190" />



---

## Monitoring & Logs

### Prometheus

Prometheus scrapes `/metrics` from all three app containers every 15 seconds. The FastAPI app exposes this endpoint automatically via `prometheus-fastapi-instrumentator`.

Metrics collected per container:
- `http_requests_total` — total request count by handler, method, status
- `http_request_duration_seconds` — latency histogram
- `up` — whether the container is reachable

### Grafana

Grafana connects to Prometheus and visualizes the data across four panels:

| Panel | Query | What it shows |
|---|---|---|
| Request rate | `rate(http_requests_total{handler=~"/status\|/data"}[1m])` | Live req/sec per container |
| p95 Latency | `histogram_quantile(0.95, ...)` | 95th percentile response time |
| Error rate | `rate(http_requests_total{status=~"4xx\|5xx"}[1m])` | Failed requests over time |
| Containers up | `up{job="fastapi"}` | 1 = healthy, 0 = down |

> **Screenshots of the Grafana dashboard below.**

### Container logs

Every request is logged to stdout by Uvicorn and captured by Docker:

```bash
# Follow logs from all containers
docker compose logs -f

# Follow a specific container
docker compose logs -f app1
```

---

## How ~100 req/sec is handled

The system is set up to handle around 100–150 req/sec without any changes.

Three app containers × 4 Uvicorn workers each = **12 worker processes** running in parallel. Each worker handles one request at a time, and FastAPI itself is async — I/O-bound work doesn't block the event loop.

At ~10–12 req/sec per worker, 12 workers gives roughly 120–144 req/sec of comfortable headroom before latency starts climbing.

Nginx distributes load across containers using `least_conn`, which keeps the work balanced even when some requests take longer.

If the system needed to go higher — say 500–1000 req/sec — the path is straightforward: add more containers to the Compose file (or scale the service in Kubernetes), and Nginx picks them up automatically. No code changes needed.

To verify this during testing:

```bash
# Send 1000 requests at 100 concurrent connections
hey -n 1000 -c 100 http://localhost/status
```

---

## Zero-Downtime Deployment

The deployment script updates one container at a time with a short pause between each:

```bash
docker compose up -d --no-deps app1
sleep 5
docker compose up -d --no-deps app2
sleep 5
docker compose up -d --no-deps app3
```

While `app1` is restarting, Nginx is still routing traffic to `app2` and `app3`. Users never hit a container mid-restart. By the time `app3` is updated, `app1` and `app2` are already serving the new version.

The error rate panel in Grafana stays at zero throughout the entire deployment — which is the clearest way to verify it's actually working.

---

## Running Locally

**Prerequisites:** Docker, Docker Compose

```bash
# 1. Clone the repo
git clone https://github.com/your-username/your-repo.git
cd your-repo

# 2. Copy the example env file and fill in values
cp .env.example .env

# 3. Start everything
docker compose up -d

# 4. Verify containers are up
docker compose ps
```

| Service | URL |
|---|---|
| API (via Nginx) | http://localhost |
| Grafana | http://localhost:3000 |
| Prometheus | http://localhost:9090 |

Default Grafana login: `admin` / value of `GRAFANA_PASSWORD` in your `.env`

To run the test suite locally:

```bash
pip install -r requirements.txt
pytest tests/
```

---

## Screenshots

### Grafana Dashboard — Live metrics

<img width="1808" height="994" alt="Screenshot from 2026-05-21 16-23-16" src="https://github.com/user-attachments/assets/4813137d-7b39-488f-a834-02f907f4594e" />


---

### Request Rate Panel — Under load

> <img width="705" height="299" alt="Screenshot from 2026-05-21 16-38-11" src="https://github.com/user-attachments/assets/520202d6-70e5-4f4b-b09e-477523978f69" />


---

### Containers Up Panel — All 3 healthy

> <img width="705" height="299" alt="Screenshot from 2026-05-21 16-39-09" src="https://github.com/user-attachments/assets/34cf0c7b-7822-4c89-9ef9-e5ffe1a37d9f" />


---

### p95 Latency Panel

<img width="705" height="299" alt="Screenshot from 2026-05-21 16-39-50" src="https://github.com/user-attachments/assets/925d8fa8-d6b4-40e7-b971-efb76ef76b9f" />

---

### Error Rate During Rolling Deploy

>  <img width="705" height="299" alt="Screenshot from 2026-05-21 16-44-42" src="https://github.com/user-attachments/assets/90636dc2-e9b2-4206-b900-6bfa8796bc5f" />


---

### GitHub Actions — Successful pipeline run

> 

---

### Prometheus Targets — All UP

> 

---

## Project Structure

```
├── app/
│   ├── main.py                  # FastAPI application
│   └── tests/
│       └── test_api.py          # basic endpoint tests
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── prometheus.yml
│   │   └── dashboards/
│   │       └── dashboards.yml
│   └── dashboards/
│       └── fastapi.json
├── .github/
│   └── workflows/
│       └── deploy.yml           # CI/CD pipeline
├── Dockerfile
├── docker-compose.yml
├── nginx.conf
├── prometheus.yml
├── requirements.txt
├── .env.example
└── README.md
```
