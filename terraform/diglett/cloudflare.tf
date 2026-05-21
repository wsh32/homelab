data "cloudflare_zone" "main" {
  zone_id = var.cloudflare_zone_id
}

locals {
  headscale_hostname = "${var.headscale_subdomain}.${data.cloudflare_zone.main.name}"
}

# DNS-only A record pointing at the home IP.
# proxied = false — Cloudflare proxy strips the TS2021 upgrade header.
# content is a placeholder; the cloudflare-ddns container updates it at runtime.
# ignore_changes prevents Terraform from resetting the IP on subsequent applies.
resource "cloudflare_record" "headscale" {
  zone_id = var.cloudflare_zone_id
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
  description = "Public Headscale URL — set as headscale_url in terraform.tfvars for other modules"
  value       = "https://${local.headscale_hostname}"
}
