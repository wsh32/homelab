# tenderloin-web

Static site for tenderloin.ai, sourced from https://github.com/wsh32/tenderloin.

The `tenderloin-sync` container (git-sync) polls the repo every 60s and maintains a
symlink at `/mnt/nas/docker/tenderloin-web/tenderloin` pointing to the latest worktree.
nginx serves from that symlink. No manual content deployment needed.

## Cloudflare Tunnel

Public traffic arrives via the `cloudflared-tenderloin` tunnel on `diglett-infra`.
Managed entirely by Terraform (`terraform/diglett/cloudflare.tf`).
