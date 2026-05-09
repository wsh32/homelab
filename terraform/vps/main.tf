resource "digitalocean_ssh_key" "homelab" {
  name       = "homelab"
  public_key = var.ssh_public_key
}

resource "digitalocean_droplet" "vps" {
  name   = "homelab-vps"
  region = var.do_region
  size   = var.do_size
  image  = "ubuntu-24-04-x64"

  ssh_keys = [digitalocean_ssh_key.homelab.fingerprint]

  # ansible-pull handles all software config after first boot.
  # Run: ansible-playbook ansible/vps.yml to bootstrap.
}

resource "digitalocean_firewall" "vps" {
  name = "homelab-vps"

  droplet_ids = [digitalocean_droplet.vps.id]

  # SSH — operator access only
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # GitHub webhook
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9000"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Headscale coordination (HTTPS)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Headscale DERP relay
  inbound_rule {
    protocol         = "udp"
    port_range       = "41641"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

output "vps_ip" {
  value = digitalocean_droplet.vps.ipv4_address
}
