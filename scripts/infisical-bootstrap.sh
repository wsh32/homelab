#!/usr/bin/env bash
# Bootstrap Infisical on a freshly provisioned redstone-infisical VM.
# Creates admin user, organization, workspace, and machine identity.
# Run once after Terraform + cloud-init completes.
#
# Usage:
#   INFISICAL_HOST=http://192.168.0.21:8080 ./scripts/infisical-bootstrap.sh
#
# Outputs workspace_id, client_id, client_secret — add to terraform.tfvars.

set -euo pipefail

INFISICAL_HOST="${INFISICAL_HOST:-http://192.168.0.21:8080}"
ADMIN_EMAIL="${INFISICAL_ADMIN_EMAIL:-admin@homelab.local}"
ADMIN_PASSWORD="${INFISICAL_ADMIN_PASSWORD:-}"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "Error: set INFISICAL_ADMIN_PASSWORD"
  exit 1
fi

echo "==> Waiting for Infisical at ${INFISICAL_HOST}..."
until curl -sf "${INFISICAL_HOST}/api/status" > /dev/null; do
  sleep 3
done

echo "==> Bootstrapping Infisical..."
BOOTSTRAP_OUTPUT=$(infisical bootstrap \
  --domain "$INFISICAL_HOST" \
  --email "$ADMIN_EMAIL" \
  --password "$ADMIN_PASSWORD" \
  --ignore-if-bootstrapped \
  --output json)

echo "$BOOTSTRAP_OUTPUT" | jq .

echo ""
echo "==> Add the following to terraform.tfvars:"
echo "infisical_workspace_id = \"$(echo "$BOOTSTRAP_OUTPUT" | jq -r '.workspaceId')\""
echo "infisical_client_id    = \"$(echo "$BOOTSTRAP_OUTPUT" | jq -r '.clientId')\""
echo "infisical_client_secret = \"$(echo "$BOOTSTRAP_OUTPUT" | jq -r '.clientSecret')\""
