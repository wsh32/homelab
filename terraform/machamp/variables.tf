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

variable "services_gpu_mappings" {
  description = "Proxmox hardware mapping names for GPU passthrough to machamp-media (e.g. [\"quadro-p2200\"]). Create mappings via pvesh first -- see GPU passthrough section in docs/runbook.md."
  type        = list(string)
  default     = []
}

variable "ai_gpu_mappings" {
  description = "Proxmox hardware mapping names for GPU passthrough to machamp-ai (e.g. [\"rtx-6000-ada\"]). Create mappings via pvesh first -- see GPU passthrough section in docs/runbook.md."
  type        = list(string)
  default     = []
}

variable "ai_disk_datastore" {
  description = "Proxmox datastore for the machamp-ai root/model disk. Use an NVMe-backed datastore -- the 512GB model store will not fit on the boot SSD's local-lvm."
  type        = string
  default     = "local-lvm"
}
