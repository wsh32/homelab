#!/bin/sh
# Builds the SF Scramble Vite frontend from the git-sync working copy into the
# shared /dist volume that nginx serves, and rebuilds whenever git-sync checks
# out a new commit on main.
#
# The git-sync mount is read-only, so the source is copied into a writable
# workspace (/build) before running npm.
set -eu

SRC=/repo/scramble/frontend
WORK=/build
DIST=/dist

checkout() { readlink /repo/scramble 2>/dev/null || echo none; }

echo "scramble-frontend-build: waiting for git-sync to populate the repo..."
while [ ! -f "$SRC/package.json" ]; do sleep 2; done

build() {
  echo "scramble-frontend-build: building..."
  mkdir -p "$WORK"
  # Overlay the latest source onto the workspace, preserving node_modules.
  cp -a "$SRC/." "$WORK/"
  cd "$WORK"
  npm ci
  npm run build
  # Swap the freshly built assets into the served directory.
  mkdir -p "$DIST"
  find "$DIST" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -a dist/. "$DIST/"
  echo "scramble-frontend-build: build complete"
}

build
CURRENT=$(checkout)
while true; do
  sleep 30
  NEW=$(checkout)
  if [ "$NEW" != "$CURRENT" ]; then
    echo "scramble-frontend-build: new commit ($NEW), rebuilding"
    build
    CURRENT=$NEW
  fi
done
