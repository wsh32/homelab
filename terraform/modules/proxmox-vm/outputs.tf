output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "name" {
  description = "VM hostname"
  value       = proxmox_virtual_environment_vm.vm.name
}

output "ip_address" {
  description = "VM IP address (without CIDR)"
  value       = var.ip_address != null ? split("/", var.ip_address)[0] : null
}

output "ipv4_addresses" {
  description = "All IPv4 addresses reported by the QEMU guest agent"
  value       = proxmox_virtual_environment_vm.vm.ipv4_addresses
}
