variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g. 'https://192.168.0.x:8006')"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox API username (e.g. 'terraform@pve')"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox API password"
  type        = string
  sensitive   = true
}

variable "infisical_host" {
  description = "Infisical instance URL"
  type        = string
}

variable "infisical_client_id" {
  description = "Infisical machine identity client ID"
  type        = string
}

variable "infisical_client_secret" {
  description = "Infisical machine identity client secret"
  type        = string
  sensitive   = true
}

variable "infisical_workspace_id" {
  description = "Infisical workspace/project ID"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key to inject into all VMs"
  type        = string
}
