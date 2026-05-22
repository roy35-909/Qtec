# Production-Style FastAPI Platform with Docker, Terraform, CI/CD, Monitoring, and Kubernetes

This repository demonstrates a small production-style platform for a FastAPI service. It includes Docker-based containerization, Terraform for AWS infrastructure, GitHub Actions for CI/CD, Prometheus and Grafana for observability, and Kubernetes manifests for orchestration, rolling updates, and horizontal scaling.

---

## Table of Contents

- [What We Built](#what-we-built)
- [System Architecture](#system-architecture)
- [Tech Stack](#tech-stack)
- [API](#api)
- [Containerization Approach](#containerization-approach)
- [Terraform Infrastructure](#terraform-infrastructure)
- [CI/CD Pipeline](#cicd-pipeline)
- [Kubernetes Orchestration](#kubernetes-orchestration)
- [Deployment Process](#deployment-process)
- [Zero-Downtime Deployment](#zero-downtime-deployment)
- [Logging and Monitoring](#logging-and-monitoring)
- [How the System Handles ~100 Requests/sec](#how-the-system-handles-100-requestssec)
- [Running Locally](#running-locally)
- [Project Structure](#project-structure)

---

## What We Built

- A FastAPI application with `/status`, `/data`, and `/metrics` endpoints.
- A Dockerized runtime that can run locally, on a provisioned AWS EC2 instance, or in Kubernetes.
- Terraform infrastructure that provisions the AWS networking and compute layer.
- A GitHub Actions pipeline that tests, builds, pushes, and deploys the application image.
- Kubernetes manifests for a rolling-update Deployment, a Service, and a HorizontalPodAutoscaler.
- Prometheus and Grafana for application metrics, health, and latency monitoring.
 - Argo CD for GitOps-style continuous delivery and automated cluster synchronization.

## System Architecture

The platform has two supported runtime paths:

```text
Developer push
  │
  ▼
GitHub Actions
  ├── tests the app
  ├── builds and pushes the Docker image
  └── deploys to AWS or updates Kubernetes

AWS path:
User -> Nginx on EC2 -> app1/app2/app3 containers -> FastAPI
                         │
                         ├-> /metrics -> Prometheus -> Grafana
                         └-> /status, /data -> application traffic

Kubernetes path:
User -> Service -> Deployment pods -> FastAPI
                  │
                  ├-> readiness/liveness probes
                  └-> HPA scales replicas on CPU usage
```

Terraform provisions the AWS host used by the Compose-based deployment. Kubernetes manifests provide an alternative orchestrated runtime with native rolling updates and autoscaling.

---

## Tech Stack

| Layer | Tool |
|---|---|
| API | Python, FastAPI, Uvicorn |
| Containerization | Docker, Docker Compose |
| Reverse proxy | Nginx |
| CI/CD | GitHub Actions |
| Infrastructure as Code | Terraform |
| Orchestration | Kubernetes |
| Metrics | Prometheus, prometheus-fastapi-instrumentator |
| Dashboards | Grafana |
| Load testing | hey |

## API

The FastAPI app exposes three key endpoints:

- `GET /status` returns a health response and timestamp.
- `POST /data` accepts a JSON payload and echoes the key back.
- `GET /metrics` is exposed by `prometheus-fastapi-instrumentator` for scraping.

Example requests:

```bash
curl http://localhost/status

curl -X POST http://localhost/data \
  -H "Content-Type: application/json" \
  -d '{"key":"environment","value":"production"}'
```

## Containerization Approach

The application is packaged in [app/Dockerfile](app/Dockerfile) with a production-friendly layout:

- Based on `python:3.12-slim` to keep the image small.
- Runs as a non-root user (`appuser`).
- Installs dependencies from `requirements.txt` with `pip`.
- Starts Uvicorn on port `8000` with 4 worker processes.
- Uses the `PORT` environment variable so the runtime can be configured without editing code.

The Compose stack in [docker-compose.yml](docker-compose.yml) runs three application containers (`app1`, `app2`, `app3`) behind Nginx, plus Prometheus and Grafana for monitoring.

## Terraform Infrastructure

The [terraform/](terraform) folder provisions the AWS runtime used by the deployment workflow.

It creates:

- A VPC with DNS support.
- One public subnet.
- An internet gateway and route table.
- A security group for SSH, HTTP, Nginx, Grafana, and Prometheus.
- An EC2 instance with a 20 GB `gp3` root disk.
- A key pair for SSH access.

Key Terraform files:

- [terraform/main.tf](terraform/main.tf)
- [terraform/variable.tf](terraform/variable.tf)
- [terraform/outputs.tf](terraform/outputs.tf)

Open ports in the security group:

- `22` for SSH, restricted by `allowed_ssh_cidr`.
- `80` for HTTP traffic.
- `8079` for the Nginx proxy used by the Compose deployment.
- `3000` for Grafana.
- `9099` for Prometheus.

Terraform outputs the server IP, DNS name, app URL, Grafana URL, and Prometheus URL after `apply`.

## CI/CD Pipeline

The workflow in [.github/workflows/deploy.yml](.github/workflows/deploy.yml) runs on pushes to `main`.

Flow:

1. Test job checks out the code, installs Python 3.12 dependencies, and runs `pytest`.
2. Build job builds the Docker image from `app/`.
3. Push job logs in to Docker Hub and pushes the image tagged with the commit SHA.
4. Deploy job SSHs into the server, clones or updates the repo, writes the runtime `.env`, and updates the running containers one by one.

Required secrets:

- `DOCKER_USERNAME`
- `DOCKER_PASSWORD`
- `SERVER_HOST`
- `SERVER_USER`
- `SSH_PRIVATE_KEY`
- `GH_TOKEN`
- `GRAFANA_PASSWORD`

## Kubernetes Orchestration

The [k8s/](k8s) folder contains Kubernetes manifests for the application:

- [k8s/namespace.yaml](k8s/namespace.yaml)
- [k8s/deployment.yaml](k8s/deployment.yaml)
- [k8s/service.yaml](k8s/service.yaml)
- [k8s/hpa.yaml](k8s/hpa.yaml)
- [k8s/kustomization.yaml](k8s/kustomization.yaml)

The Deployment is configured for rolling updates with `maxUnavailable: 0` and `maxSurge: 1`. It also includes readiness and liveness probes against `/status` so traffic only reaches healthy pods.

The Service exposes the app with a `LoadBalancer`, and the HorizontalPodAutoscaler scales from 3 to 10 replicas based on CPU utilization.

Apply the manifests with:

```bash
kubectl apply -k k8s
```

### Argo CD (GitOps)

You can use Argo CD as a GitOps entry point to keep the `k8s/` folder in sync with your cluster.

1. Install Argo CD (single-cluster):

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

2. Expose the Argo CD server locally (port-forward) or configure an ingress/LoadBalancer:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# then open http://localhost:8080
```

3. Apply the Argo CD Application manifest included in this repo to point Argo CD at the `k8s/` directory:

```bash
kubectl apply -f k8s/argocd/application.yaml -n argocd
```

Argo CD will then synchronize the `k8s/` directory in this repository into the `qtech` namespace. The Application uses `automated` sync with `prune` and `selfHeal` enabled so changes in Git are applied automatically.

Notes:
- The Application `repoURL` points to `https://github.com/roy35-909/Qtec.git` — change this to your fork if needed.
- For production clusters, secure the Argo CD server (TLS, ingress) and restrict who can create Applications.


## Deployment Process

There are two practical deployment paths in this repository:

### AWS host + Docker Compose

1. Terraform provisions the EC2 host and its networking.
2. GitHub Actions builds and pushes the Docker image.
3. The deploy job SSHs into the host.
4. The host pulls the new image and updates `app1`, `app2`, and `app3` sequentially.

### Kubernetes

1. Push the image to the registry.
2. Update the image tag in the Deployment manifest if needed.
3. Apply the manifest with `kubectl apply -k k8s`.
4. Kubernetes performs a rolling update automatically.

## Zero-Downtime Deployment

The Docker Compose path updates one app container at a time:

```bash
docker compose up -d --no-deps app1
sleep 5
docker compose up -d --no-deps app2
sleep 5
docker compose up -d --no-deps app3
```

Nginx keeps routing traffic to the remaining healthy containers while one container restarts. That means there is always capacity to serve requests.

The Kubernetes path achieves the same outcome with the Deployment rolling-update strategy and readiness probes. New pods must become healthy before they receive traffic, so old pods stay in service until the replacement pods are ready.

## Logging and Monitoring

The app logs to stdout through Uvicorn, so Docker and Kubernetes can capture the logs natively.

Prometheus scrapes the FastAPI `/metrics` endpoint every 15 seconds in the Compose-based monitoring stack. Grafana then visualizes request rate, latency, errors, and container health.

Useful log commands:

```bash
docker compose logs -f
docker compose logs -f app1
kubectl logs -f deploy/qtech-api -n qtech
```

## Screenshots

### Grafana Overview

<img width="825" height="458" alt="Screenshot from 2026-05-21 20-49-35" src="https://github.com/user-attachments/assets/3dcc357e-c2cd-4d95-b0ca-9861ebb11ee8" />

<img width="1459" height="562" alt="Screenshot from 2026-05-21 20-47-06" src="https://github.com/user-attachments/assets/3f0e9bea-ef34-42ea-aa2d-24354b3f5190" />

### Grafana Panels

#### Live Metrics

<img width="1808" height="994" alt="Screenshot from 2026-05-21 16-23-16" src="https://github.com/user-attachments/assets/4813137d-7b39-488f-a834-02f907f4594e" />

#### Request Rate (under load)

> <img width="705" height="299" alt="Screenshot from 2026-05-21 16-38-11" src="https://github.com/user-attachments/assets/520202d6-70e5-4f4b-b09e-477523978f69" />

#### Containers Up — all healthy

> <img width="705" height="299" alt="Screenshot from 2026-05-21 16-39-09" src="https://github.com/user-attachments/assets/34cf0c7b-7822-4c89-9ef9-e5ffe1a37d9f" />

#### p95 Latency

<img width="705" height="299" alt="Screenshot from 2026-05-21 16-39-50" src="https://github.com/user-attachments/assets/925d8fa8-d6b4-40e7-b971-efb76ef76b9f" />

#### Error Rate During Rolling Deploy

>  <img width="705" height="299" alt="Screenshot from 2026-05-21 16-44-42" src="https://github.com/user-attachments/assets/90636dc2-e9b2-4206-b900-6bfa8796bc5f" />


## How the System Handles ~100 Requests/sec

The Compose deployment is sized for roughly 100 to 150 requests per second under normal conditions.

Why it works:

- Three app containers run in parallel.
- Each container starts Uvicorn with 4 workers.
- That gives 12 workers total.
- Nginx uses `least_conn`, so requests spread across the least busy container.
- The app is lightweight and mostly I/O bound, so it stays efficient under moderate concurrency.

In Kubernetes, the same app can scale beyond that baseline because the HPA can add more pods when CPU rises.

For a quick load test:

```bash
hey -n 1000 -c 100 http://localhost/status
```

## Running Locally

Prerequisites: Docker and Docker Compose.

```bash
docker compose up -d
docker compose ps
```

If you want to test the Kubernetes manifests locally on a cluster:

```bash
kubectl apply -k k8s
```

## Project Structure

```text
├── app/
│   ├── Dockerfile
│   ├── main.py
│   ├── requirements.txt
│   └── tests/
├── k8s/
│   ├── deployment.yaml
│   ├── hpa.yaml
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── service.yaml
├── terraform/
│   ├── main.tf
│   ├── outputs.tf
│   ├── variable.tf
│   └── terraform.tfvars
├── .github/
│   └── workflows/
│       └── deploy.yml
├── docker-compose.yml
├── nginx.conf
├── prometheus.yml
└── README.md
```
