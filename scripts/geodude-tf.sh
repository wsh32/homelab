#!/usr/bin/env bash
# Run Terraform against the geodude Proxmox node.
#
# The bpg/proxmox provider ignores ~/.ssh/config, so it can't route SSH
# through the tailscale2 HTTP CONNECT proxy on its own. This script starts
# a socat relay (localhost:12222 → geodude SSH via the proxy) before running
# Terraform, then tears it down on exit.
#
# Usage:
#   scripts/geodude-tf.sh plan
#   scripts/geodude-tf.sh apply
#   scripts/geodude-tf.sh import <resource> <id>
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Start socat relay: localhost:12222 → geodude:22 via tailscale2 HTTP CONNECT proxy
socat TCP-LISTEN:12222,fork,reuseaddr \
  PROXY:127.0.0.1:geodude.corgi-census.ts.net:22,proxyport=1055 &
SOCAT_PID=$!
trap "kill $SOCAT_PID 2>/dev/null || true" EXIT

HTTPS_PROXY=http://localhost:1055 terraform -chdir="$REPO_ROOT/terraform/geodude" "$@"
