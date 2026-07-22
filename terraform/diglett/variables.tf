variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g. https://192.168.0.6:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (e.g. terraform@pam!terraform=<uuid>)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key to install on all VMs"
  type        = string
}

variable "timezone" {
  description = "System timezone for all VMs (e.g. America/Los_Angeles)"
  type        = string
  default     = "UTC"
}

variable "vm_password" {
  description = "Password for the ubuntu user on all VMs"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone > DNS > Edit permission"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID -- owns the Zero Trust tunnels (found in the dashboard URL or any zone's Overview sidebar)"
  type        = string
}

variable "homelab_zone" {
  description = "Zone name (key in cloudflare_web_zone_ids) hosting Headscale and Authentik, e.g. 'wesleysoohoo.me'"
  type        = string
}

variable "headscale_subdomain" {
  description = "Subdomain for Headscale public endpoint (e.g. 'headscale' → headscale.example.com)"
  type        = string
  default     = "headscale"
}

variable "authentik_subdomain" {
  description = "Subdomain for the public Authentik OIDC endpoint (e.g. 'auth' → auth.example.com)"
  type        = string
  default     = "auth"
}

variable "cloudflare_web_zone_ids" {
  description = "Map of zone name to Cloudflare zone ID for every zone this stack manages -- the homelab zone (var.homelab_zone) plus any diglett-web public zones (e.g. { \"wesleysoohoo.me\" = \"abc123\", \"tenderloin.ai\" = \"def456\" })"
  type        = map(string)

  validation {
    condition     = contains(keys(var.cloudflare_web_zone_ids), var.homelab_zone)
    error_message = "cloudflare_web_zone_ids must include an entry for var.homelab_zone (${var.homelab_zone})."
  }
}
