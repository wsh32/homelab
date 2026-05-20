# Headscale through Cloudflare Tunnel — Why It Doesn't Work

## Background

The DNS VM runs Headscale (self-hosted Tailscale coordination server) behind a Cloudflare Zero Trust Tunnel
(cloudflared). The intent was to expose Headscale publicly via `headscale.wesleysoohoo.me` without opening
any ports on the Eero, using Cloudflare as the ingress.

This document explains why that fails, what was tried, and what the resolution options are.

## Root Cause: Cloudflare Strips Custom Upgrade Headers

Tailscale clients connect to a Headscale server using a custom WebSocket-like protocol called TS2021.
The HTTP upgrade handshake uses a non-standard header value:

```
GET /ts2021 HTTP/1.1
Upgrade: tailscale-control-protocol
Connection: Upgrade
```

Cloudflare's proxy only passes through standard WebSocket upgrades (`Upgrade: websocket`). When it sees
`Upgrade: tailscale-control-protocol`, it treats the connection as plain HTTP, strips the Upgrade header,
and forwards a regular HTTP request to the origin. Headscale receives a request with no Upgrade header
and returns an error.

This is a fundamental Cloudflare proxy limitation — not a misconfiguration.

## What Was Tried

### 1. Default HTTP tunnel

Initial tunnel config used `http://headscale:8080` as the service URL. The client error was:

```
register request Post "https://headscale.wesleysoohoo.me/machine/register" unexpected HTTP response: 500
```

Headscale logs showed the connection arriving without the Upgrade header.

### 2. WebSocket service URL (`ws://`)

Changed the Terraform tunnel config to use a `ws://` service URL, which tells cloudflared to request
a WebSocket upgrade when connecting to the origin:

```hcl
# terraform/diglett/cloudflare.tf
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "headscale" {
  config {
    ingress_rule {
      hostname = local.headscale_hostname
      service  = "ws://headscale:8080"
      origin_request {
        no_tls_verify = true
        http2_origin  = false
        proxy_type    = ""
      }
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}
```

This causes cloudflared to upgrade its connection to the origin as `Upgrade: websocket`, but Cloudflare
still strips the `Upgrade: tailscale-control-protocol` header on the client-facing side. The mismatch
remains — cloudflared sees a plain HTTP request, upgrades to a standard WebSocket toward Headscale, but
Headscale is expecting TS2021, not a generic WebSocket connection.

### 3. Verified WebSockets enabled in Cloudflare dashboard

Confirmed "WebSockets" is enabled in the Cloudflare zone settings. This controls whether Cloudflare passes
`Upgrade: websocket` through — it does not affect custom Upgrade header values.

### 4. Confirmed LAN access works

After adding a `ports` mapping that was missing from the Docker Compose file:

```yaml
# services/dns/docker-compose.yml
headscale:
  ports:
    - "8080:8080"
```

LAN access works:

```
tailscale up --login-server http://192.168.0.2:8080
```

Nodes connect and register successfully over the LAN path.

## Why a Nginx WebSocket Translator Won't Work

One proposed workaround is to put an nginx reverse proxy between cloudflared and Headscale, translating
the Upgrade header in both directions:

```
Tailscale client → Cloudflare → cloudflared → nginx (translator) → Headscale
```

This fails for multiple reasons:

**Request side**: Cloudflare strips the custom Upgrade header before it reaches cloudflared. Nginx receives
a plain HTTP request with no Upgrade header. For nginx to inject `Upgrade: tailscale-control-protocol`,
it would have to hardcode the value with no basis for knowing which Upgrade type was intended. This breaks
if Headscale ever changes the protocol identifier.

**Response side**: After Headscale accepts the upgrade, it sends:

```
HTTP/1.1 101 Switching Protocols
Upgrade: tailscale-control-protocol
Connection: Upgrade
```

Nginx would need to rewrite the `Upgrade` response header to `websocket` for cloudflared to accept the
`101`. Standard nginx WebSocket proxying (`proxy_set_header Upgrade $http_upgrade`) only rewrites request
headers, not response headers. Rewriting the `101` response requires the Lua module (`ngx_lua`) or a
custom-compiled nginx.

**After the 101**: The connection becomes raw TCP carrying Tailscale Noise frames. Any buffering or
protocol inspection by nginx at this stage corrupts the stream.

The result is a fragile, multi-point hack that breaks silently on any cloudflared, nginx, or Headscale
update.

## Resolution Options

### Option A: Port forward on Eero (recommended)

Forward TCP 443 → `192.168.0.2:443` on the Eero. Set the Cloudflare DNS record for
`headscale.wesleysoohoo.me` to DNS-only (orange cloud off), pointing to the home IP. Headscale
handles TLS directly via its built-in ACME support or a local cert.

Pros: One moving part. Headscale receives the connection unmodified.  
Cons: Exposes port 443 of the DNS VM to the public internet. Requires a static home IP or DDNS.

### Option B: LAN-only for now

Leave Headscale accessible only on the LAN at `http://192.168.0.2:8080`. Enroll new nodes only
from the local network. Remote enrollment is not possible.

Pros: Zero additional infrastructure. Already working.  
Cons: Cannot onboard devices that are not physically on the LAN.

### Option C: Separate VM outside the tunnel

Run a minimal Headscale relay or DERP server on a cheap cloud VPS (Hetzner, Vultr, etc.) with a
public IP. Cloudflare Tunnel is not involved — the VPS has a real port 443. More complex but keeps
the Eero closed.

## Current Status

LAN access is working. Option A (port forward) is the intended resolution. The Cloudflare Tunnel
config (`ws://headscale:8080`) is kept in place for the cloudflared → Headscale leg; only the
Cloudflare proxy (orange cloud) needs to be disabled for the DNS record.
