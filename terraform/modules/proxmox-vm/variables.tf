variable "node_name" {
  description = "Proxmox node to deploy the VM on"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 299
    error_message = "vm_id must be in the homelab range 100–299 (Machamp: 100–199, Diglett: 200–299)."
  }
}

variable "name" {
  description = "VM hostname"
  type        = string
}

variable "description" {
  description = "VM description shown in Proxmox UI"
  type        = string
  default     = ""
}

variable "cores" {
  description = "Number of vCPU cores"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM in MB"
  type        = number
  default     = 2048
}

variable "disk_size_gb" {
  description = "Root disk size in GB"
  type        = number
  default     = 20
}

variable "datastore" {
  description = "Proxmox datastore for VM disk"
  type        = string
  default     = "local-lvm"
}

variable "image_file_id" {
  description = "Proxmox file ID of the cloud image to use (from proxmox_virtual_environment_download_file)"
  type        = string
}

variable "ip_address" {
  description = "Static IP address with CIDR (e.g. 192.168.0.21/24)"
  type        = string
  validation {
    condition     = can(cidrhost(var.ip_address, 0))
    error_message = "ip_address must be a valid CIDR notation address (e.g. 192.168.0.21/24)."
  }
}

variable "gateway" {
  description = "Default gateway"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers for the VM"
  type        = list(string)
}

variable "ssh_public_key" {
  description = "SSH public key for the default user"
  type        = string
  validation {
    condition     = length(var.ssh_public_key) > 0
    error_message = "ssh_public_key must not be empty."
  }
}

variable "timezone" {
  description = "System timezone (e.g. America/Los_Angeles)"
  type        = string
  default     = "UTC"
}

variable "swap_size_gb" {
  description = "Swap file size in GB. 0 disables swap."
  type        = number
  default     = 0
}

variable "vm_password" {
  description = "Password for the ubuntu user (enables console and SSH password login)"
  type        = string
  sensitive   = true
}

variable "tailscale_auth_key" {
  description = "Tailscale one-time auth key for this VM"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.tailscale_auth_key) > 0
    error_message = "tailscale_auth_key must not be empty."
  }
}

variable "extra_runcmd" {
  description = "Additional shell commands to run at first boot, appended to runcmd"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "List of Proxmox tags"
  type        = list(string)
  default     = []
}
