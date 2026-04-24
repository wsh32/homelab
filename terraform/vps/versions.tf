terraform {
  required_version = ">= 1.9"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }

  # State stored locally on operator laptop — VPS cannot manage its own existence.
  # Back up terraform.tfstate as an encrypted attachment in Vaultwarden.
  backend "local" {
    path = "terraform.tfstate"
  }
}
