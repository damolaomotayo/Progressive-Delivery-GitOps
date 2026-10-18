#!/usr/bin/env bash
# End-to-end proof (about 8-10 minutes):
#   1. v2 (good)    -> rolls out step by step and becomes the stable version
#   2. v3-bad       -> analysis catches the errors, rollout aborts, v2 keeps serving
#   3. v2 again     -> Git is put back to a good state
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
NS=demo

jp() { kubectl -n "$NS" get rollouts.argoproj.io demo-app -o jsonpath="$1" 2>/dev/null || true; }
phase() { jp '{.status.phase}'; }
image() { jp '{.spec.template.spec.containers[0].image}'; }

healthy_with() {
  [ "$(phase)" = "Healthy" ] && [[ "$(image)" == *":$1" ]] &&
    [ "$(jp '{.status.stableRS}')" = "$(jp '{.status.currentPodHash}')" ]
}
aborted() { [ "$(phase)" = "Degraded" ]; }
bad_pods_gone() {
  ! kubectl -n "$NS" get pods -l app=demo-app -o jsonpath='{.items[*].spec.containers[*].image}' | grep -q 'v3-bad'
}

wait_for() { # description timeout-seconds command...
  local desc=$1 timeout=$2
  shift 2
  local end=$((SECONDS + timeout))
  until "$@"; do
    if [ "$SECONDS" -ge "$end" ]; then
      echo "FAIL  ${desc} (timed out; phase=$(phase))"
      exit 1
    fi
    sleep 5
  done
  echo "ok    ${desc}"
}

echo "Starting state: Git says $(image)"
./scripts/release.sh v1
wait_for "v1 is deployed and healthy" 300 healthy_with v1

echo "--- Good release: v2"
./scripts/release.sh v2
wait_for "v2 rolled out and promoted to stable" 420 healthy_with v2

echo "--- Bad release: v3-bad (watch it live: kubectl-argo-rollouts get rollout demo-app -n demo --watch)"
./scripts/release.sh v3-bad
wait_for "bad release detected and rollout aborted automatically" 420 aborted
wait_for "canary pods removed, only v2 is serving" 180 bad_pods_gone

echo "--- Put Git back to the good version"
./scripts/release.sh v2
wait_for "back to healthy on v2" 300 healthy_with v2

echo
echo "All checks passed."
