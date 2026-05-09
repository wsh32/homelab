variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g. https://192.168.0.5:8006)"
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

variable "tailscale_auth_key" {
  description = "Tailscale reusable auth key for VM provisioning"
  type        = string
  sensitive   = true
}
