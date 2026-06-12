#!/usr/bin/env bash
# Grant Seerr admin permissions to a user by Jellyfin username.
# Usage: seerr-grant-admin.sh <jellyfin-username>
set -euo pipefail

USERNAME="${1:?Usage: $0 <jellyfin-username>}"
SEERR_URL="http://localhost:5055"
API_KEY=$(python3 -c "import json; print(json.load(open('/mnt/nas/docker/seerr/settings.json'))['main']['apiKey'])")

USER_ID=$(curl -sf "$SEERR_URL/api/v1/user?take=100" \
  -H "X-Api-Key: $API_KEY" \
  | python3 -c "
import sys, json
users = json.load(sys.stdin)['results']
match = [u for u in users if u.get('jellyfinUsername','').lower() == '$USERNAME'.lower()]
if not match:
    print('', end='')
else:
    print(match[0]['id'], end='')
")

if [[ -z "$USER_ID" ]]; then
  echo "Error: user '$USERNAME' not found in Seerr. Have they logged in at least once?" >&2
  exit 1
fi

curl -sf -X PUT "$SEERR_URL/api/v1/user/$USER_ID" \
  -H "X-Api-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"permissions": 2}' \
  | python3 -c "import sys,json; u=json.load(sys.stdin); print(f'Granted admin to {u[\"jellyfinUsername\"]} (id={u[\"id\"]})')"
