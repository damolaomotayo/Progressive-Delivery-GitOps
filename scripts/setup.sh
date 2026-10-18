#!/usr/bin/env bash
# One-time host setup (Amazon Linux 2023 or Ubuntu 22.04+):
# git + Docker, a single-node Kubernetes (k3s), the Argo Rollouts CLI,
# and the three demo images (v1, v2, v3-bad) loaded into k3s.
set -euo pipefail
cd "$(dirname "$0")/.."

K3S_VERSION="${K3S_VERSION:-v1.31.4+k3s1}"
ROLLOUTS_VERSION="${ROLLOUTS_VERSION:-v1.7.2}"

if command -v dnf >/dev/null 2>&1; then
  sudo dnf install -y git docker
elif command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y git docker.io curl
else
  echo "Unsupported OS: install git and docker manually." >&2
  exit 1
fi
sudo systemctl enable --now docker

if ! command -v k3s >/dev/null 2>&1; then
  echo "Installing k3s ${K3S_VERSION}..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" sh -s - --write-kubeconfig-mode 644
fi
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Waiting for the Kubernetes node to be Ready..."
for _ in $(seq 1 60); do
  kubectl get nodes 2>/dev/null | grep -q ' Ready' && break
  sleep 3
done
kubectl get nodes

case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  *) echo "Unsupported CPU: $(uname -m)" >&2; exit 1 ;;
esac
if ! command -v kubectl-argo-rollouts >/dev/null 2>&1; then
  echo "Installing Argo Rollouts CLI ${ROLLOUTS_VERSION}..."
  sudo curl -fsSL -o /usr/local/bin/kubectl-argo-rollouts \
    "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/kubectl-argo-rollouts-linux-${ARCH}"
  sudo chmod +x /usr/local/bin/kubectl-argo-rollouts
fi

./scripts/build_images.sh

# Make kubectl work in new shells.
grep -q 'rancher/k3s/k3s.yaml' ~/.bashrc 2>/dev/null || echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc

echo
echo "Setup complete. Next: export GITHUB_USER and GITHUB_TOKEN, then ./scripts/bootstrap.sh"
