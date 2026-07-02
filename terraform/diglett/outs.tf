resource "local_sensitive_file" "secrets" {
  filename        = "${path.module}/outs/secrets.yml"
  file_permission = "0600"
  content = yamlencode({
    tenderloin_tunnel_token = nonsensitive(cloudflare_zero_trust_tunnel_cloudflared.diglett_web.tunnel_token)
    authentik_tunnel_token  = nonsensitive(cloudflare_zero_trust_tunnel_cloudflared.authentik.tunnel_token)
  })
}
