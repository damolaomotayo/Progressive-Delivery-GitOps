#!/usr/bin/env bash
# Build three versions of the app and load them straight into k3s
# (no container registry needed for this demo).
#   v1       good
#   v2       good (the "new feature" release)
#   v3-bad   returns HTTP 500 on half of requests (the bad release)
set -euo pipefail
cd "$(dirname "$0")/.."

build() {
  local tag=$1 error_rate=$2
  echo "Building demo-app:${tag} (ERROR_RATE=${error_rate})"
  sudo docker build -q -t "demo-app:${tag}" \
    --build-arg "APP_VERSION=${tag}" --build-arg "ERROR_RATE=${error_rate}" .
  sudo docker save "demo-app:${tag}" | sudo k3s ctr images import -
}

build v1 0
build v2 0
build v3-bad 0.5
echo "Images ready."
