#!/usr/bin/env bash
# reset-nfs-state.sh -- wipe NFS-persisted service state before a fresh homelab rebuild.
#
# Run this from alakazam-deploy (or any host with /mnt/nas mounted) BEFORE running
# ansible playbooks on a fresh Proxmox install. Media files (/mnt/nas/media) are
# never touched.
#
# Usage:
#   ./scripts/deploy/reset-nfs-state.sh [--all] [service ...]
#
# Examples:
#   ./scripts/deploy/reset-nfs-state.sh --all          # wipe everything
#   ./scripts/deploy/reset-nfs-state.sh jellyfin qbittorrent

set -euo pipefail

NAS=/mnt/nas/docker

# Services whose entire config dir can be wiped (re-initialized by Ansible/arr-init).
RESETTABLE=(
  # machamp-media -- auth state or generated config that conflicts with fresh Infisical
  jellyfin
  bazarr
  prowlarr
  radarr
  sabnzbd
  sonarr
  seerr
  qbittorrent
  # diglett-dns -- stateless enough to rebuild
  adguardhome
  headplane
)

# Services intentionally excluded from --all (require careful handling):
#   step-ca          -- root CA; regenerating invalidates all existing certs
#   traefik/acme     -- ACME cert cache; losing it triggers re-issue (rate-limit risk)
#   headscale        -- node registrations; losing it deregisters all Tailscale nodes
#   postgres-backup  -- backup archive; not state to wipe
#   vaultwarden-backup -- backup archive; not state to wipe
#   authentik        -- user/OIDC config; rebuilt by infra.yml

usage() {
  echo "Usage: $0 [--all] [service ...]"
  echo "Resettable services: ${RESETTABLE[*]}"
  exit 1
}

[[ $# -eq 0 ]] && usage

if [[ "$1" == "--all" ]]; then
  targets=("${RESETTABLE[@]}")
else
  targets=("$@")
fi

echo "NFS base: $NAS"
echo ""

for svc in "${targets[@]}"; do
  dir="$NAS/$svc"
  if [[ ! -d "$dir" ]]; then
    echo "SKIP  $svc -- $dir not found"
    continue
  fi

  # Extra guard: refuse to wipe excluded services even if named explicitly
  case "$svc" in
    step-ca|headscale|postgres-backup|vaultwarden-backup)
      echo "SKIP  $svc -- excluded (requires manual handling)"
      continue
      ;;
  esac

  echo -n "WIPE  $dir ... "
  rm -rf "${dir:?}"/*
  echo "done"
done

echo ""
echo "Done. Re-run ansible playbooks to reinitialize wiped services."
