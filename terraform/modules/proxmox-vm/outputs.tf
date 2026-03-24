output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "name" {
  description = "VM hostname"
  value       = proxmox_virtual_environment_vm.vm.name
}

output "ip_address" {
  description = "VM IP address"
  value       = proxmox_virtual_environment_vm.vm.ipv4_addresses
}
