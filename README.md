# Progressive Delivery and GitOps

Git is the only way to change what runs in the cluster. Releasing a new version means committing a new image tag. Argo CD syncs it, and Argo Rollouts releases it gradually (20% → 60% → 100%) while Prometheus metrics judge the new version. A bad release is stopped and rolled back automatically, with no human involved.

```
 you ──git push──▶ GitHub repo (private)
                       │  watched by
                       ▼
                    Argo CD ──applies──▶ Rollout (canary 20% → 60% → 100%)
                                              │ new pods expose /metrics
                    Argo Rollouts ◀── Prometheus scrapes the canary pods
                    (AnalysisTemplate: error ratio < 5% ? else ABORT + roll back)
```

## What runs where

| Piece | Role |
|---|---|
| k3s | Single-node Kubernetes on your EC2 instance |
| Argo CD | GitOps engine: makes the cluster match Git, reverts manual drift (`selfHeal`) |
| Argo Rollouts | Replaces Deployment with a `Rollout` that supports canary steps and auto-abort |
| Prometheus | Collects request/error counts per pod |
| `demo-app` | Tiny Python service. Images: `v1`, `v2` (good) and `v3-bad` (50% HTTP 500) |
| `loadgen` | Sends steady traffic so there are metrics to judge |

## Repo layout

```
app/          Demo service (standard library only)
k8s/app/      Rollout, AnalysisTemplate, Service, load generator
k8s/monitoring/  Prometheus
argocd/       Argo CD Applications (what to sync from Git)
scripts/      setup, bootstrap, release, verify, destroy
tests/        Unit tests
```

## Run it on EC2

**Instance:** Ubuntu 22.04/24.04 or Amazon Linux 2023, **t3.large** (2 vCPU, 8 GB) or bigger, 20 GB disk. No inbound ports needed except SSH. The instance needs internet access (no AWS permissions needed).

**GitHub token (once):** GitHub → Settings → Developer settings → Fine-grained tokens → Generate. Repository access: only this repo. Permission: **Contents = Read and write**.

```bash
# 1. Get the code (HTTPS URL, not SSH)
git clone https://github.com/<you>/progressive-delivery-gitops.git && cd progressive-delivery-gitops

# 2. Unit tests (no installs needed)
python3 -m unittest discover -s tests

# 3. Install git, Docker, k3s v1.31.4, Argo Rollouts CLI v1.7.2; build the 3 images (~3 min)
./scripts/setup.sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 4. Install Argo CD v2.13.3 + Argo Rollouts v1.7.2 and connect your repo (~3 min)
export GITHUB_USER=<you> GITHUB_TOKEN=<token>
./scripts/bootstrap.sh

# 5. Prove it works (~8-10 min). Ends with "All checks passed."
./scripts/verify.sh
```

**Watch a release live** (second SSH terminal), then release from the first:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl-argo-rollouts get rollout demo-app -n demo --watch
# in the other terminal:
./scripts/release.sh v2        # good: steps through 20% → 60% → 100%
./scripts/release.sh v3-bad    # bad: analysis fails, rollout aborts, v2 keeps serving
./scripts/release.sh v2        # restore Git to the good version
```

**Argo CD UI (optional):**

```bash
kubectl -n argocd port-forward svc/argocd-server 8443:443
# from your laptop: ssh -L 8443:localhost:8443 <user>@<ec2-ip>, then open https://localhost:8443
# login: admin / password printed by bootstrap.sh
```

**Tear down:** `./scripts/destroy.sh`, then terminate the EC2 instance.

## Key ideas to be able to explain

- **GitOps:** Git is the desired state; Argo CD is a controller that continuously reconciles the cluster to it. `kubectl edit` changes get reverted (`selfHeal`).
- **Progressive delivery:** expose a new version to a small share of traffic first, and promote only if metrics stay healthy.
- **Why metrics, not probes:** `v3-bad` passes its readiness probe (`/healthz` is fine) but fails real requests. Only analysis of request errors catches it.
- **Aborted ≠ reverted in Git:** an abort stops the rollout and keeps serving the old version, but Git still says `v3-bad` until you revert it (the last step of `verify.sh`).

## Limitations (kept simple on purpose)

- Traffic split is by pod count (20% of 5 pods = 1 pod). Precise percentages need an ingress or service mesh (NGINX, Istio, Traefik).
- Images are built on the host and loaded into k3s. A real pipeline would build in CI and push to a registry (ECR/GHCR).
- Single node, no TLS, Prometheus keeps 2 hours of data.
