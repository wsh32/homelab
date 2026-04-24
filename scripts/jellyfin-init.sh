#!/usr/bin/env bash
# Initialize Jellyfin headlessly via the /Startup/* API.
# Run once after first container start; idempotent (checks wizard status first).
#
# Usage:
#   JELLYFIN_HOST=http://192.168.0.11:8096 \
#   JELLYFIN_ADMIN_PASSWORD=<password> \
#   ./scripts/jellyfin-init.sh

set -euo pipefail

JELLYFIN_HOST="${JELLYFIN_HOST:-http://192.168.0.11:8096}"
ADMIN_USER="${JELLYFIN_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${JELLYFIN_ADMIN_PASSWORD:-}"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "Error: set JELLYFIN_ADMIN_PASSWORD"
  exit 1
fi

echo "==> Waiting for Jellyfin at ${JELLYFIN_HOST}..."
until curl -sf "${JELLYFIN_HOST}/health" > /dev/null; do
  sleep 3
done

echo "==> Checking wizard status..."
WIZARD_STATUS=$(curl -sf "${JELLYFIN_HOST}/Startup/Configuration" | jq -r '.UICulture // empty' || echo "")
if [[ -n "$WIZARD_STATUS" ]]; then
  echo "==> Wizard already complete, skipping."
  exit 0
fi

echo "==> Setting locale..."
curl -sf -X POST "${JELLYFIN_HOST}/Startup/Configuration" \
  -H "Content-Type: application/json" \
  -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'

echo "==> Creating admin user..."
curl -sf -X POST "${JELLYFIN_HOST}/Startup/User" \
  -H "Content-Type: application/json" \
  -d "{\"Name\":\"${ADMIN_USER}\",\"Password\":\"${ADMIN_PASSWORD}\"}"

echo "==> Configuring remote access..."
curl -sf -X POST "${JELLYFIN_HOST}/Startup/RemoteAccess" \
  -H "Content-Type: application/json" \
  -d '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}'

echo "==> Completing wizard..."
curl -sf -X POST "${JELLYFIN_HOST}/Startup/Complete"

echo "==> Jellyfin init complete."
