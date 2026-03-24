resource "proxmox_virtual_environment_vm" "vm" {
  node_name = var.node
  vm_id     = var.vm_id
  name      = var.name
  tags      = var.tags

  clone {
    vm_id   = data.proxmox_virtual_environment_vms.template.vms[0].vm_id
    full    = true
    retries = 3
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore
    size         = var.disk_size
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.ip_address != "" ? var.ip_address : "dhcp"
        gateway = var.ip_address != "" ? var.gateway : null
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_keys]
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node

  source_raw {
    data      = local.cloud_init_config
    file_name = "${var.name}-cloud-init.yaml"
  }
}

data "proxmox_virtual_environment_vms" "template" {
  node_name = var.node
  filters {
    name = var.template_name
  }
}

locals {
  cloud_init_config = <<-EOT
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - qemu-guest-agent

    runcmd:
      - systemctl enable --now qemu-guest-agent
      - curl -fsSL https://tailscale.com/install.sh | sh
      - tailscale up --authkey=${var.tailscale_auth_key} --hostname=${var.name}
      ${var.user_data != "" ? "# additional user_data follows" : ""}
    ${var.user_data}
  EOT
}
