variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "do_region" {
  description = "DigitalOcean region slug"
  type        = string
  default     = "nyc3"
}

variable "do_size" {
  description = "Droplet size slug"
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "ssh_public_key" {
  description = "SSH public key to install on the VPS"
  type        = string
}
