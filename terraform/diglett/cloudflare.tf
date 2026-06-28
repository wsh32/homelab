data "cloudflare_zone" "main" {
  zone_id = var.cloudflare_homelab_zone_id
}

locals {
  headscale_hostname  = "${var.headscale_subdomain}.${data.cloudflare_zone.main.name}"
  authentik_hostname  = "${var.authentik_subdomain}.${data.cloudflare_zone.main.name}"
}

# DNS-only A record pointing at the home IP.
# proxied = false -- Cloudflare proxy strips the TS2021 upgrade header.
# content is a placeholder; the cloudflare-ddns container updates it at runtime.
# ignore_changes prevents Terraform from resetting the IP on subsequent applies.
resource "cloudflare_record" "headscale" {
  zone_id = var.cloudflare_homelab_zone_id
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
  account_id = data.cloudflare_zone.main.account_id
  name       = "authentik-oidc"
  secret     = random_id.tunnel_secret.b64_std
}

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "authentik" {
  account_id = data.cloudflare_zone.main.account_id
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
  zone_id = var.cloudflare_homelab_zone_id
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

# ── tenderloin.ai ─────────────────────────────────────────────────────────────

data "cloudflare_zone" "tenderloin" {
  zone_id = var.cloudflare_tenderloin_zone_id
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "tenderloin" {
  account_id = data.cloudflare_zone.tenderloin.account_id
  name       = "tenderloin-web"
  secret     = random_id.tenderloin_tunnel_secret.b64_std
}

resource "random_id" "tenderloin_tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "tenderloin" {
  account_id = data.cloudflare_zone.tenderloin.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tenderloin.id

  config {
    ingress_rule {
      hostname = data.cloudflare_zone.tenderloin.name
      service  = "http://tenderloin-web:80"
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# CNAME tenderloin.ai → <tunnel-id>.cfargotunnel.com (proxied through Cloudflare)
resource "cloudflare_record" "tenderloin_root" {
  zone_id = var.cloudflare_tenderloin_zone_id
  name    = "@"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.tenderloin.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1  # auto TTL (required when proxied = true)
}

output "tenderloin_tunnel_token" {
  description = "Cloudflare Tunnel token -- written to /etc/tenderloin-tunnel.env on diglett-infra by the infra Ansible role"
  value       = cloudflare_zero_trust_tunnel_cloudflared.tenderloin.tunnel_token
  sensitive   = true
}
