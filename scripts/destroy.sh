#!/usr/bin/env bash
# Remove Kubernetes (and everything in it) from this machine.
# To stop all AWS cost, also terminate the EC2 instance.
set -euo pipefail

if [ -x /usr/local/bin/k3s-uninstall.sh ]; then
  sudo /usr/local/bin/k3s-uninstall.sh
fi
sudo docker rmi demo-app:v1 demo-app:v2 demo-app:v3-bad 2>/dev/null || true
rm -f ~/.git-credentials
echo "Removed. Revoke the GitHub token if you no longer need it."
