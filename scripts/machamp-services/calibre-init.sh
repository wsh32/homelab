#!/usr/bin/env bash
# Set Calibre-Web admin password via the cps.py CLI after first container start.
# Run once; idempotent (password set is non-destructive on re-run).
#
# Usage:
#   CALIBRE_ADMIN_PASSWORD=<password> ./scripts/calibre-init.sh

set -euo pipefail

CALIBRE_ADMIN_PASSWORD="${CALIBRE_ADMIN_PASSWORD:-}"

if [[ -z "$CALIBRE_ADMIN_PASSWORD" ]]; then
  echo "Error: set CALIBRE_ADMIN_PASSWORD"
  exit 1
fi

echo "==> Waiting for calibre-web container to be running..."
until docker inspect calibre-web --format '{{.State.Running}}' 2>/dev/null | grep -q true; do
  sleep 3
done

echo "==> Setting admin password..."
docker exec calibre-web \
  python3 /app/calibre-web/cps.py \
  -p /config/app.db \
  -s "admin:${CALIBRE_ADMIN_PASSWORD}"

echo "==> Calibre-Web init complete."
