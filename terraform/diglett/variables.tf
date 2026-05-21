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

variable "tailscale_auth_key" {
  description = "Tailscale reusable auth key for VM provisioning"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone > DNS > Edit permission"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the domain used for Headscale"
  type        = string
}

variable "headscale_subdomain" {
  description = "Subdomain for Headscale public endpoint (e.g. 'headscale' → headscale.example.com)"
  type        = string
  default     = "headscale"
}

variable "headscale_webui_key" {
  description = "Fernet encryption key for headscale-webui API key storage. Generate with: python3 -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\""
  type        = string
  sensitive   = true
}
