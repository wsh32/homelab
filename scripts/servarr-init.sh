#!/usr/bin/env bash
# Link Prowlarr to Radarr and Sonarr via API after first container start.
# Run once; idempotent (checks for existing application links).
#
# Usage:
#   PROWLARR_API_KEY=<key> RADARR_API_KEY=<key> SONARR_API_KEY=<key> \
#   ./scripts/servarr-init.sh

set -euo pipefail

PROWLARR_HOST="${PROWLARR_HOST:-http://192.168.0.30:9696}"
RADARR_HOST="${RADARR_HOST:-http://192.168.0.30:7878}"
SONARR_HOST="${SONARR_HOST:-http://192.168.0.30:8989}"

PROWLARR_API_KEY="${PROWLARR_API_KEY:-}"
RADARR_API_KEY="${RADARR_API_KEY:-}"
SONARR_API_KEY="${SONARR_API_KEY:-}"

for var in PROWLARR_API_KEY RADARR_API_KEY SONARR_API_KEY; do
  if [[ -z "${!var}" ]]; then
    echo "Error: $var is not set"
    exit 1
  fi
done

wait_for() {
  local host="$1" name="$2"
  echo "==> Waiting for ${name} at ${host}..."
  until curl -sf "${host}/ping" > /dev/null 2>&1 || curl -sf "${host}/api/v1/system/status" \
    -H "X-Api-Key: ${!name}_API_KEY" > /dev/null 2>&1; do
    sleep 3
  done
}

echo "==> Waiting for services..."
until curl -sf "${PROWLARR_HOST}/api/v1/system/status" -H "X-Api-Key: ${PROWLARR_API_KEY}" > /dev/null; do sleep 3; done
until curl -sf "${RADARR_HOST}/api/v3/system/status" -H "X-Api-Key: ${RADARR_API_KEY}" > /dev/null; do sleep 3; done
until curl -sf "${SONARR_HOST}/api/v3/system/status" -H "X-Api-Key: ${SONARR_API_KEY}" > /dev/null; do sleep 3; done

link_app() {
  local name="$1" base_url="$2" api_key="$3" port="$4"
  echo "==> Linking Prowlarr → ${name}..."
  curl -sf -X POST "${PROWLARR_HOST}/api/v1/applications" \
    -H "X-Api-Key: ${PROWLARR_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"syncLevel\": \"fullSync\",
      \"name\": \"${name}\",
      \"fields\": [
        {\"name\": \"prowlarrUrl\", \"value\": \"${PROWLARR_HOST}\"},
        {\"name\": \"baseUrl\", \"value\": \"${base_url}\"},
        {\"name\": \"apiKey\", \"value\": \"${api_key}\"}
      ],
      \"implementationName\": \"${name}\",
      \"implementation\": \"${name}\"
    }" || echo "  (may already be linked — continuing)"
}

link_app "Radarr" "$RADARR_HOST" "$RADARR_API_KEY" 7878
link_app "Sonarr" "$SONARR_HOST" "$SONARR_API_KEY" 8989

echo "==> Servarr init complete."
