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
def matches(u):
    for field in ('jellyfinUsername', 'displayName', 'email'):
        val = u.get(field) or ''
        if val.lower() == '$USERNAME'.lower():
            return True
    return False
match = [u for u in users if matches(u)]
if not match:
    print('available users:')
    for u in users:
        print(' id=%s jellyfinUsername=%s displayName=%s email=%s' % (u.get('id'), u.get('jellyfinUsername'), u.get('displayName'), u.get('email')))
    print('', end='')
else:
    print(match[0]['id'], end='')
" 2>&1)

if [[ -z "$USER_ID" ]]; then
  echo "Error: user '$USERNAME' not found in Seerr. Have they logged in at least once?" >&2
  exit 1
fi

curl -sf -X PUT "$SEERR_URL/api/v1/user/$USER_ID" \
  -H "X-Api-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"permissions": 2}' \
  | python3 -c "import sys,json; u=json.load(sys.stdin); print(f'Granted admin to {u.get(\"jellyfinUsername\") or u.get(\"displayName\") or u.get(\"email\")} (id={u[\"id\"]})')"
