#!/bin/sh
# Runs the SF Scramble FastAPI backend from the git-sync working copy and
# restarts it whenever git-sync checks out a new commit on main.
#
# git-sync maintains /repo/scramble as a symlink to the current checkout; the
# symlink target changes on every new commit, which is how we detect updates.
set -eu

REPO=/repo/scramble/backend

checkout() { readlink /repo/scramble 2>/dev/null || echo none; }

echo "scramble-backend: waiting for git-sync to populate the repo..."
while [ ! -f "$REPO/requirements.txt" ]; do sleep 2; done

install_deps() {
  echo "scramble-backend: installing dependencies..."
  pip install --no-cache-dir --root-user-action=ignore -r "$REPO/requirements.txt"
}

APP_PID=""
start() {
  install_deps
  # cd via the symlink so a new checkout is picked up on restart.
  ( cd "$REPO" && exec python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 ) &
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
