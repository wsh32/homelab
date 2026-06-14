#!/usr/bin/env bash
# Create n8n owner account via the setup API on first start.
# Run once; idempotent (endpoint errors if owner already exists).
#
# Usage:
#   N8N_ADMIN_EMAIL=<email> N8N_ADMIN_PASSWORD=<password> ./scripts/n8n-init.sh

set -euo pipefail

N8N_HOST="${N8N_HOST:-http://192.168.0.30:5678}"
N8N_ADMIN_EMAIL="${N8N_ADMIN_EMAIL:-}"
N8N_ADMIN_PASSWORD="${N8N_ADMIN_PASSWORD:-}"
N8N_ADMIN_FIRST="${N8N_ADMIN_FIRST:-Admin}"
N8N_ADMIN_LAST="${N8N_ADMIN_LAST:-User}"

for var in N8N_ADMIN_EMAIL N8N_ADMIN_PASSWORD; do
  if [[ -z "${!var}" ]]; then
    echo "Error: $var is not set"
    exit 1
  fi
done

echo "==> Waiting for n8n at ${N8N_HOST}..."
until curl -sf "${N8N_HOST}/healthz" > /dev/null; do
  sleep 3
done

echo "==> Creating owner account..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${N8N_HOST}/api/v1/owner/setup" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"${N8N_ADMIN_EMAIL}\",
    \"password\": \"${N8N_ADMIN_PASSWORD}\",
    \"firstName\": \"${N8N_ADMIN_FIRST}\",
    \"lastName\": \"${N8N_ADMIN_LAST}\"
  }")

if [[ "$RESPONSE" == "200" ]] || [[ "$RESPONSE" == "400" ]]; then
  echo "==> n8n init complete (HTTP $RESPONSE -- 400 means owner already exists)."
else
  echo "Error: unexpected HTTP $RESPONSE"
  exit 1
fi
