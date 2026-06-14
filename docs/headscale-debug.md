# Headscale Debugging

All commands run on the DNS VM (`ssh ubuntu@192.168.0.2`) unless noted.

---

## Container status

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
# headscale should show 0.0.0.0:443->443/tcp
# cloudflare-ddns should be Up
```

```bash
docker logs headscale --tail 50 --follow
docker logs cloudflare-ddns --tail 50
```

---

## TLS / ACME

```bash
# Check cert issuance in logs
docker logs headscale | grep -i -E "acme|cert|tls|letsencrypt"

# Check cert files exist on disk
ls /mnt/nas/docker/headscale/cache/

# Inspect the issued cert (from outside the VM)
echo | openssl s_client -connect headscale.wesleysoohoo.me:443 2>/dev/null | openssl x509 -noout -dates -subject

# Quick health check from outside your LAN
curl -v https://headscale.wesleysoohoo.me/health
```

---

## Port / connectivity

```bash
# Confirm headscale is bound to 443 on the host
ss -tlnp | grep 443

# Test port is reachable from the LAN
curl -v https://192.168.0.2/health --resolve headscale.wesleysoohoo.me:443:192.168.0.2

# Test from outside (run on a device not on your LAN)
curl https://headscale.wesleysoohoo.me/health
```

---

## DDNS

```bash
# Check cloudflare-ddns updated the A record
docker logs cloudflare-ddns

# Confirm what IP Cloudflare has for the record (run anywhere)
dig +short headscale.wesleysoohoo.me

# Confirm your current home IP
curl -s https://ifconfig.me
# Should match the dig output above
```

---

## Nodes and keys

```bash
# List all enrolled nodes
docker exec headscale headscale nodes list

# List pre-auth keys
docker exec headscale headscale preauthkeys list --user main

# List users
docker exec headscale headscale users list

# Show routes advertised by nodes
docker exec headscale headscale routes list
```

---

## Enrollment

```bash
# Enroll a new node (run on the node being enrolled)
tailscale up --login-server https://headscale.wesleysoohoo.me

# If the node shows a login URL, approve it on the server
docker exec headscale headscale nodes register --user main --key <nodekey>

# Or use a pre-auth key to skip manual approval
tailscale up --login-server https://headscale.wesleysoohoo.me --auth-key <preauth-key>
```

---

## Config and env

```bash
# Dump the resolved headscale config (shows env var overrides applied)
docker exec headscale headscale config dump

# Check the env file written by cloud-init
sudo cat /etc/headscale.env

# Validate the config file directly
docker exec headscale headscale config check
```

---

## Database

```bash
# SQLite -- inspect directly (headscale must be stopped or use a copy)
docker exec headscale sqlite3 /var/lib/headscale/db.sqlite ".tables"
docker exec headscale sqlite3 /var/lib/headscale/db.sqlite "SELECT * FROM nodes;"
```

---

## Full restart

```bash
cd ~/services/diglett-dns   # or wherever docker-compose.yml lives on the DNS VM
docker compose down && docker compose up -d
docker compose logs -f
```
