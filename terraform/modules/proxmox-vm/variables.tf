variable "node" {
  description = "Proxmox node to deploy the VM on (e.g. 'anton', 'nuc')"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID (must be unique across the cluster)"
  type        = number
}

variable "name" {
  description = "VM hostname"
  type        = string
}

variable "cores" {
  description = "Number of vCPUs"
  type        = number
  default     = 2
}

variable "memory" {
  description = "RAM in MB"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 20
}

variable "datastore" {
  description = "Proxmox storage pool for the VM disk"
  type        = string
  default     = "local-lvm"
}

variable "template_name" {
  description = "Name of the cloud-init VM template to clone"
  type        = string
  default     = "ubuntu-cloud"
}

variable "ip_address" {
  description = "Static IP address in CIDR notation (e.g. '192.168.0.10/24'). Leave empty for DHCP."
  type        = string
  default     = ""
}

variable "gateway" {
  description = "Default gateway IP"
  type        = string
  default     = "192.168.0.1"
}

variable "dns_servers" {
  description = "List of DNS server IPs"
  type        = list(string)
  default     = ["192.168.0.2"] # AdGuard Home on nuc-infra
}

variable "ssh_public_keys" {
  description = "SSH public keys to inject via cloud-init"
  type        = string
}

variable "tailscale_auth_key" {
  description = "Tailscale pre-auth key for this VM (from Infisical)"
  type        = string
  sensitive   = true
}

variable "user_data" {
  description = "Additional cloud-init user-data (merged with base template)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "List of Proxmox tags for the VM"
  type        = list(string)
  default     = []
}
