terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.73"
    }
  }
}

# Cloud-init user-data snippet — uploaded to Proxmox local snippets storage.
# Requires snippets enabled on the local datastore (one-time Proxmox UI step:
#   Datacenter > Storage > local > Edit > check "Snippets").
locals {
  swap_config = var.swap_size_gb > 0 ? "swap:\n  filename: /swapfile\n  size: ${var.swap_size_gb}G\n  maxsize: ${var.swap_size_gb}G\n\n" : ""
}

resource "proxmox_virtual_environment_file" "user_data" {
  node_name    = var.node_name
  content_type = "snippets"
  datastore_id = "local"

  source_raw {
    file_name = "${var.name}-user-data.yaml"
    data      = <<-EOF
      #cloud-config
      hostname: ${var.name}
      fqdn: ${var.name}.home
      timezone: ${var.timezone}
      locale: en_US.UTF-8

      manage_etc_hosts: true

      users:
        - name: ubuntu
          groups: sudo
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.ssh_public_key}
          ssh_import_id:
            - gh:wsh32
          sudo: ALL=(ALL) NOPASSWD:ALL

      ssh_pwauth: true

      chpasswd:
        list: |
          ubuntu:${var.vm_password}
        expire: false

      ${local.swap_config}package_update: true
      package_upgrade: true
      package_reboot_if_required: true
      packages:
        - qemu-guest-agent

      runcmd:
        - curl -fsSL https://tailscale.com/install.sh | sh
        - tailscale up --authkey=${var.tailscale_auth_key} --hostname=${var.name}
        - systemctl enable --now qemu-guest-agent
      ${var.user_data_extra != "" ? "\n${var.user_data_extra}" : ""}
    EOF
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  node_name   = var.node_name
  vm_id       = var.vm_id
  name        = var.name
  description = var.description
  tags        = var.tags

  on_boot = true

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  # Root disk — cloned from the downloaded cloud image
  disk {
    datastore_id = var.datastore
    file_id      = var.image_file_id
    interface    = "virtio0"
    size         = var.disk_size_gb
    discard      = "on"
    iothread     = true
  }

  # Cloud-init drive
  disk {
    datastore_id = var.datastore
    interface    = "ide2"
    file_format  = "raw"
    size         = 4
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # QEMU guest agent (installed via cloud-init)
  agent {
    enabled = true
    trim    = true
  }

  operating_system {
    type = "l26"
  }

  # Cloud-init configuration
  initialization {
    datastore_id = var.datastore

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }

    user_data_file_id = proxmox_virtual_environment_file.user_data.id
  }

  lifecycle {
    ignore_changes = [
      # Don't recreate VM if the source image is re-downloaded
      disk[0].file_id,
    ]
  }
}
