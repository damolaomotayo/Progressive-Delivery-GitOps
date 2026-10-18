#!/usr/bin/env bash
# "Release" = change the image tag in Git. Argo CD notices and syncs it,
# then Argo Rollouts releases it gradually.
#   ./scripts/release.sh v2
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: ./scripts/release.sh <v1|v2|v3-bad>}"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

sed -i -E "s#(image: demo-app:).*#\1${TAG}#" k8s/app/rollout.yaml

if git diff --quiet -- k8s/app/rollout.yaml; then
  echo "Git already says ${TAG}. Nothing to commit."
else
  git add k8s/app/rollout.yaml
  git -c user.name="${GIT_USER:-gitops-demo}" -c user.email="${GIT_EMAIL:-gitops-demo@example.com}" \
    commit -q -m "release ${TAG}"
  git push -q origin HEAD
  echo "Pushed release ${TAG} to Git."
fi

# Ask Argo CD to check Git now instead of waiting for its 3 minute poll.
kubectl -n argocd annotate applications.argoproj.io demo-app argocd.argoproj.io/refresh=hard --overwrite >/dev/null
