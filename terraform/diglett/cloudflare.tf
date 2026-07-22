locals {
  # The homelab zone hosts headscale.* and auth.*; its ID comes from
  # cloudflare_web_zone_ids via var.homelab_zone.
  homelab_zone_id = var.cloudflare_web_zone_ids[var.homelab_zone]

  headscale_hostname = "${var.headscale_subdomain}.${var.homelab_zone}"
  authentik_hostname = "${var.authentik_subdomain}.${var.homelab_zone}"
}

# DNS-only A record pointing at the home IP.
# proxied = false -- Cloudflare proxy strips the TS2021 upgrade header.
# content is a placeholder; the cloudflare-ddns container updates it at runtime.
# ignore_changes prevents Terraform from resetting the IP on subsequent applies.
resource "cloudflare_record" "headscale" {
  zone_id = local.homelab_zone_id
  name    = var.headscale_subdomain
  content = "0.0.0.0"
  type    = "A"
  proxied = false
  ttl     = 60

  lifecycle {
    ignore_changes = [content]
  }
}

output "headscale_url" {
  description = "Public Headscale URL -- set as headscale_url in terraform.tfvars for other modules"
  value       = "https://${local.headscale_hostname}"
}

# Cloudflare Tunnel running on diglett-infra, proxying Authentik's OIDC endpoints.
# Only /application/o/ is exposed publicly -- everything else returns 404.
# This allows OIDC device enrollment from outside the LAN without a port forward.
resource "cloudflare_zero_trust_tunnel_cloudflared" "authentik" {
  account_id = var.cloudflare_account_id
  name       = "authentik-oidc"
  secret     = random_id.tunnel_secret.b64_std
}

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "authentik" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.authentik.id

  config {
    ingress_rule {
      hostname = local.authentik_hostname
      service  = "http://authentik-server:9000"
    }
    # Catch-all for other hostnames (none expected)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# CNAME auth.<zone> → <tunnel-id>.cfargotunnel.com (proxied through Cloudflare)
resource "cloudflare_record" "authentik" {
  zone_id = local.homelab_zone_id
  name    = var.authentik_subdomain
  content = "${cloudflare_zero_trust_tunnel_cloudflared.authentik.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1  # auto TTL (required when proxied = true)
}

output "authentik_tunnel_token" {
  description = "Cloudflare Tunnel token -- written to /etc/cloudflare-tunnel.env on diglett-infra by the infra Ansible role"
  value       = cloudflare_zero_trust_tunnel_cloudflared.authentik.tunnel_token
  sensitive   = true
}

output "authentik_public_url" {
  description = "Public Authentik OIDC base URL"
  value       = "https://${local.authentik_hostname}"
}

# ── diglett-web public tunnel ─────────────────────────────────────────────────
# One tunnel for all public web services on diglett-web.
# Cloudflare forwards all traffic to Traefik; Traefik routes by Host header.
# Services and their public hostnames are declared in network.yml.

locals {
  web_public_services = [
    for s in local.vms["diglett-web"].services : s
    if lookup(s, "public_hostname", null) != null
  ]
}

resource "random_id" "diglett_web_tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "diglett_web" {
  account_id = var.cloudflare_account_id
  name       = "diglett-web"
  secret     = random_id.diglett_web_tunnel_secret.b64_std
}

# Single catch-all ingress rule -- Traefik handles Host-based routing internally.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "diglett_web" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.diglett_web.id

  config {
    ingress_rule {
      service = "http://traefik:80"
    }
  }
}

# One CNAME per public service, pointing at the tunnel.
# Record name is derived from the hostname: strip the zone suffix to get the
# subdomain (e.g. "docs.tenderloin.ai" in zone "tenderloin.ai" → "docs"),
# or "@" for the root (e.g. "tenderloin.ai" in zone "tenderloin.ai").
resource "cloudflare_record" "web_public" {
  for_each = { for s in local.web_public_services : s.name => s }

  zone_id = var.cloudflare_web_zone_ids[each.value.cloudflare_zone]
  name    = each.value.public_hostname == each.value.cloudflare_zone ? "@" : trimsuffix(each.value.public_hostname, ".${each.value.cloudflare_zone}")
  content = "${cloudflare_zero_trust_tunnel_cloudflared.diglett_web.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1  # auto TTL (required when proxied = true)
}

output "diglett_web_tunnel_token" {
  description = "Cloudflare Tunnel token -- written to /etc/cloudflared.env on diglett-web by the web Ansible role"
  value       = cloudflare_zero_trust_tunnel_cloudflared.diglett_web.tunnel_token
  sensitive   = true
}
