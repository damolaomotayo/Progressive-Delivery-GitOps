#!/usr/bin/env bash
# Install Argo Rollouts + Argo CD, give Argo CD read access to your PRIVATE repo,
# and hand it the two Applications. After this, Git drives the cluster.
#
# Needs:  export GITHUB_USER=<your github username>
#         export GITHUB_TOKEN=<fine-grained token: this repo, Contents = Read and write>
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GITHUB_USER:?export GITHUB_USER first}"
: "${GITHUB_TOKEN:?export GITHUB_TOKEN first}"

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.3}"
ROLLOUTS_VERSION="${ROLLOUTS_VERSION:-v1.7.2}"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

REPO_URL="$(git remote get-url origin | sed -E 's#https://[^@/]+@#https://#; s#\.git$##')"
case "$REPO_URL" in
  https://github.com/*) ;;
  *) echo "Clone the repo with its HTTPS URL (found: $REPO_URL)" >&2; exit 1 ;;
esac
if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
  echo "Run this from the 'main' branch." >&2; exit 1
fi

echo "Installing Argo Rollouts ${ROLLOUTS_VERSION}..."
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts -f "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/install.yaml"

echo "Installing Argo CD ${ARGOCD_VERSION}..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "Waiting for Argo components..."
kubectl wait --for=condition=established --timeout=120s \
  crd/applications.argoproj.io crd/rollouts.argoproj.io crd/analysistemplates.argoproj.io
kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo "Giving Argo CD read access to ${REPO_URL}..."
kubectl -n argocd create secret generic repo-creds \
  --from-literal=type=git \
  --from-literal=url="${REPO_URL}" \
  --from-literal=username="${GITHUB_USER}" \
  --from-literal=password="${GITHUB_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret repo-creds argocd.argoproj.io/secret-type=repository --overwrite

# So scripts/release.sh can push commits from this machine.
git config --global credential.helper store
printf 'https://%s:%s@github.com\n' "${GITHUB_USER}" "${GITHUB_TOKEN}" > ~/.git-credentials
chmod 600 ~/.git-credentials

echo "Creating the Argo CD Applications..."
sed "s#REPO_URL_PLACEHOLDER#${REPO_URL}#" argocd/applications.yaml | kubectl apply -f -

echo "Waiting for v1 to deploy (up to 5 minutes)..."
for _ in $(seq 1 60); do
  phase="$(kubectl -n demo get rollouts.argoproj.io demo-app -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [ "$phase" = "Healthy" ] && break
  sleep 5
done
echo "Rollout phase: ${phase:-unknown}"
kubectl -n demo get pods

echo
echo "Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
echo
echo "Done. Next: ./scripts/verify.sh"
