# tenderloin-web

Static site for tenderloin.ai.

Site content is served from `/mnt/nas/docker/tenderloin-web` on the NFS share (not in this repo).
Drop an `index.html` there before starting the container.

## Cloudflare Tunnel

Public traffic arrives via the Cloudflare Tunnel on `diglett-infra`.
In the Cloudflare Zero Trust dashboard, add a Public Hostname to the existing tunnel:

- **Hostname**: `tenderloin.ai`
- **Service**: `http://tenderloin-web:80`

When this becomes a Python webserver, update the Docker Compose service and point the
tunnel to the new container port.
