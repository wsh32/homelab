variable "node_name" {
  description = "Proxmox node to deploy the VM on"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
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
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "192.168.0.1"
}

variable "dns_servers" {
  description = "DNS servers for the VM"
  type        = list(string)
  default     = ["192.168.0.2", "8.8.8.8"]
}

variable "ssh_public_key" {
  description = "SSH public key for the default user"
  type        = string
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

variable "hostpci_devices" {
  description = "List of PCI device IDs to pass through to the VM (e.g. [\"0000:01:00\"]). Find addresses with: lspci on the Proxmox host."
  type        = list(string)
  default     = []
}
