data "cloudflare_zone" "main" {
  zone_id = var.cloudflare_zone_id
}

locals {
  headscale_hostname = "${var.headscale_subdomain}.${data.cloudflare_zone.main.name}"
}

# 32-byte random secret — stored in state; used to authenticate cloudflared to Cloudflare.
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "headscale" {
  account_id = var.cloudflare_account_id
  name       = "homelab-headscale"
  secret     = random_id.tunnel_secret.b64_std
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "headscale" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.headscale.id

  config {
    ingress_rule {
      hostname = local.headscale_hostname
      service  = "http://headscale:8080"
    }
    # Required catch-all
    ingress_rule {
      service = "http_status:404"
    }
  }
}

resource "cloudflare_record" "headscale" {
  zone_id = var.cloudflare_zone_id
  name    = var.headscale_subdomain
  content = "${cloudflare_zero_trust_tunnel_cloudflared.headscale.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

output "headscale_url" {
  description = "Public Headscale URL — set as headscale_url in terraform.tfvars for other modules"
  value       = "https://${local.headscale_hostname}"
}

output "headscale_tunnel_token" {
  description = "Cloudflare tunnel token written to /etc/cloudflared.env on the DNS VM"
  value       = cloudflare_zero_trust_tunnel_cloudflared.headscale.tunnel_token
  sensitive   = true
}
