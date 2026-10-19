# STEPS: Progressive Delivery and GitOps

## Prerequisites (set these up BEFORE step 1)

| Need | Details |
|---|---|
| EC2 instance | Ubuntu 22.04/24.04 or Amazon Linux 2023, **t3.large (2 vCPU, 8 GB) or bigger**, **20 GB disk**, outbound internet. Inbound: SSH (port 22) from your IP only. No IAM role needed. |
| SSH access | Your key pair `.pem` file: `ssh -i key.pem ubuntu@<public-ip>` (Amazon Linux: `ec2-user@`). |
| Private GitHub repo | Create an empty **private** repo named `progressive-delivery-gitops`, then push this code to it from your laptop (`git remote add origin ...`, `git push -u origin main`). Argo CD reads from GitHub, so the repo must be there. |
| GitHub token | GitHub → Settings → Developer settings → Fine-grained tokens → Generate. Repository access: **only this repo**. Permission: **Contents = Read and write**. Copy the token somewhere safe; you will paste it in step 4. |
| Your GitHub username | Needed in step 4. |

Time: about 25 minutes (most of it waiting). Cost: cents per hour. Do step 7 when finished.

## Steps (run on the EC2 instance)

```bash
# 1. Get the code (use the HTTPS URL; when asked: username = yours, password = the token)
git clone https://github.com/<you>/progressive-delivery-gitops.git && cd progressive-delivery-gitops

# 2. Unit tests (no installs needed)
python3 -m unittest discover -s tests

# 3. Install git, Docker, k3s v1.31.4, Argo Rollouts CLI v1.7.2; build 3 images (~3 min)
./scripts/setup.sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 4. Install Argo CD v2.13.3 + Argo Rollouts v1.7.2, connect your repo (~3 min)
export GITHUB_USER=<you> GITHUB_TOKEN=<token>
./scripts/bootstrap.sh

# 5. Prove it works (~10 min). Ends with "All checks passed."
./scripts/verify.sh

# 6. Optional: watch a release live (second SSH terminal)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl-argo-rollouts get rollout demo-app -n demo --watch
# then in the first terminal:
./scripts/release.sh v2        # good release
./scripts/release.sh v3-bad    # bad release: gets aborted automatically
./scripts/release.sh v2        # put Git back to good

# 7. Clean up, then terminate the EC2 instance
./scripts/destroy.sh
```

## If something goes wrong

| Symptom | Fix |
|---|---|
| `Clone the repo with its HTTPS URL` | You cloned with SSH. Re-clone with the `https://` URL. |
| `Run this from the 'main' branch` | `git checkout main` |
| Push fails in `release.sh` | Token needs **Contents: Read and write** on this repo; rerun step 4 with a corrected token. |
| Pods `Pending` or the node is slow | Instance too small. Use t3.large or bigger. |
| `ImagePullBackOff` on demo-app | The images were not loaded. Run `./scripts/build_images.sh`. |
| `verify.sh` times out | Run `kubectl -n demo get pods` and `kubectl -n argocd get applications`, and send me the output. |
