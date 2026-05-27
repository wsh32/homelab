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
  description = "Cloudflare API token with Zone > DNS > Edit and Account > Cloudflare Tunnel > Edit permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the public domain"
  type        = string
}

variable "authentik_subdomain" {
  description = "Subdomain for the public Authentik OIDC endpoint (e.g. 'auth' → auth.example.com)"
  type        = string
  default     = "auth"
}

variable "services_gpu_pci_ids" {
  description = "PCI IDs for Quadro P2200 GPU passthrough to machamp-services. Find via: ssh root@machamp lspci | grep -i quadro"
  type        = list(string)
  default     = []
}
