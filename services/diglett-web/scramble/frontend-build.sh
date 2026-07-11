#!/bin/sh
# Builds the SF Scramble frontends from the git-sync working copy into the
# shared /dist volume that nginx serves, and rebuilds whenever git-sync checks
# out a new commit on main.
#
# Two apps are built into a single tree: the game SPA at the root and the
# neighborhood-builder authoring tool under /builder (it is built with
# base=/builder/). The git-sync mount is read-only, so each app's source is
# copied into a writable workspace before running npm.
set -eu

FRONTEND_SRC=/repo/scramble/frontend
BUILDER_SRC=/repo/scramble/tools/neighborhood-builder
WORK=/build
DIST=/dist

checkout() { readlink /repo/scramble 2>/dev/null || echo none; }

build_project() {
  # $1 = source dir, $2 = workspace subdir name
  src="$1"
  work="$WORK/$2"
  mkdir -p "$work"
  # Overlay the latest source onto the workspace, preserving node_modules.
  cp -a "$src/." "$work/"
  cd "$work"
  npm ci
  npm run build
}

build() {
  echo "scramble-frontend-build: building game SPA..."
  build_project "$FRONTEND_SRC" frontend
  echo "scramble-frontend-build: building neighborhood-builder..."
  build_project "$BUILDER_SRC" builder

  # Assemble one tree: game SPA at the root, builder under /builder.
  staging="$WORK/staging"
  rm -rf "$staging"
  mkdir -p "$staging/builder"
  cp -a "$WORK/frontend/dist/." "$staging/"
  cp -a "$WORK/builder/dist/." "$staging/builder/"

  # Swap the freshly built tree into the served directory.
  mkdir -p "$DIST"
  find "$DIST" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -a "$staging/." "$DIST/"
  echo "scramble-frontend-build: build complete"
}

echo "scramble-frontend-build: waiting for git-sync to populate the repo..."
while [ ! -f "$FRONTEND_SRC/package.json" ]; do sleep 2; done

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
