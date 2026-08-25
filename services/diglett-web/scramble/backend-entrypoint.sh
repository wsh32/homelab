#!/bin/sh
# Runs the SF Scramble FastAPI backend and restarts it whenever git-sync checks
# out a new commit on main.
#
# git-sync rotates and deletes old worktrees under the swapping /repo/scramble
# symlink, so a long-lived process must not run directly out of it. Copy the
# whole repo to a stable path (/srv/app) before each (re)start and run the
# backend from /srv/app/backend. The full tree is copied -- not just backend/ --
# because the app resolves sibling paths like <repo>/tools/geojson relative to
# its own location. The symlink target changes on every new commit, which is how
# we detect updates.
set -eu

SRC=/repo/scramble        # full repo checkout (git-sync symlink)
APP=/srv/app              # stable copy we run from

checkout() { readlink /repo/scramble 2>/dev/null || echo none; }

echo "scramble-backend: waiting for git-sync to populate the repo..."
while [ ! -f "$SRC/backend/requirements.txt" ]; do sleep 2; done

APP_PID=""
start() {
  # Move out of $APP before removing it: it may be the current directory, and
  # deleting the cwd breaks pip and uvicorn ("folder ... can no longer be found").
  cd /
  # Refresh the stable copy from the current checkout, then run from it.
  rm -rf "$APP"
  mkdir -p "$APP"
  cp -a "$SRC/." "$APP/"
  echo "scramble-backend: installing dependencies..."
  pip install --no-cache-dir --root-user-action=ignore -r "$APP/backend/requirements.txt"
  ( cd "$APP/backend" && exec python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 ) &
  APP_PID=$!
}

stop() {
  [ -n "$APP_PID" ] || return 0
  kill "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
  APP_PID=""
}

trap 'stop; exit 0' TERM INT

start
CURRENT=$(checkout)
while true; do
  sleep 30
  # Exit so Docker's restart policy recovers a crashed server.
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "scramble-backend: server exited, letting Docker restart the container"
    exit 1
  fi
  NEW=$(checkout)
  if [ "$NEW" != "$CURRENT" ]; then
    echo "scramble-backend: new commit ($NEW), restarting"
    stop
    start
    CURRENT=$NEW
  fi
done
