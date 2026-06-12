#!/bin/sh
# Initialize CouchDB for Obsidian LiveSync.
# Runs once as an init container; idempotent.
set -e

COUCHDB_URL="http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@couchdb:5984"

echo "Waiting for CouchDB to be ready..."
until curl -sf "${COUCHDB_URL}/_up" > /dev/null; do
  sleep 2
done

echo "Initializing single-node cluster..."
curl -sf -X POST "${COUCHDB_URL}/_cluster_setup" \
  -H "Content-Type: application/json" \
  -d '{"action":"enable_single_node","bind_address":"0.0.0.0"}' || true

echo "Creating obsidian database..."
# 412 = already exists; treat as success
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${COUCHDB_URL}/obsidian")
if [ "$STATUS" != "201" ] && [ "$STATUS" != "412" ]; then
  echo "Failed to create obsidian DB (HTTP $STATUS)"
  exit 1
fi

echo "Setting CORS headers..."
curl -sf -X PUT "${COUCHDB_URL}/_node/_local/_config/httpd/enable_cors" -d '"true"'
curl -sf -X PUT "${COUCHDB_URL}/_node/_local/_config/cors/origins" \
  -d '"app://obsidian.md,capacitor://localhost,http://localhost"'
curl -sf -X PUT "${COUCHDB_URL}/_node/_local/_config/cors/credentials" -d '"true"'
curl -sf -X PUT "${COUCHDB_URL}/_node/_local/_config/cors/methods" \
  -d '"GET, PUT, POST, HEAD, DELETE"'
curl -sf -X PUT "${COUCHDB_URL}/_node/_local/_config/cors/headers" \
  -d '"accept, authorization, content-type, origin, referer"'

echo "CouchDB init complete."
