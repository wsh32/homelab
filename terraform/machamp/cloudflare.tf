data "cloudflare_zone" "main" {
  zone_id = var.cloudflare_zone_id
}

locals {
  authentik_hostname = "${var.authentik_subdomain}.${data.cloudflare_zone.main.name}"
}

# Cloudflare Tunnel running on machamp-infra, proxying Authentik's OIDC endpoints.
# Only /application/o/ is exposed publicly — everything else returns 404.
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
  zone_id = var.cloudflare_zone_id
  name    = var.authentik_subdomain
  content = "${cloudflare_zero_trust_tunnel_cloudflared.authentik.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1  # auto TTL (required when proxied = true)
}

output "authentik_tunnel_token" {
  description = "Cloudflare Tunnel token — written to /etc/cloudflare-tunnel.env on machamp-infra by cloud-init"
  value       = cloudflare_zero_trust_tunnel_cloudflared.authentik.tunnel_token
  sensitive   = true
}

output "authentik_public_url" {
  description = "Public Authentik OIDC base URL"
  value       = "https://${local.authentik_hostname}"
}
