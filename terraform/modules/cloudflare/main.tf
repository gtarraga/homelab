data "cloudflare_zone" "stoneforge" {
  filter = {
    name = var.zone_name
  }
}

data "cloudflare_zone" "gtarraga_com" {
  filter = {
    name = var.gtarraga_com_domain
  }
}

locals {
  account_id = data.cloudflare_zone.stoneforge.account.id
  zone_id    = data.cloudflare_zone.stoneforge.id
  zone_ids = {
    (var.zone_name)           = data.cloudflare_zone.stoneforge.id
    (var.gtarraga_com_domain) = data.cloudflare_zone.gtarraga_com.id
  }
}

resource "cloudflare_zone_setting" "always_use_https" {
  for_each = local.zone_ids

  zone_id    = each.value
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_dns_record" "oidc_tunnel" {
  zone_id = local.zone_id
  name    = "oidc"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = local.account_id
  name       = "homelab"
}
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
  config = {
    ingress = [
      {
        hostname = "*.${var.zone_name}"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        hostname = "${var.gtarraga_com_domain}"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        hostname = "*.${var.gtarraga_com_domain}"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        service = "http_status:404"
      }
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "homelab" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

# Store token in AWS SSM Parameter Store

resource "aws_ssm_parameter" "cloudflare_homelab_tunnel_token" {
  name  = "/homelab/cloudflare/tunnel/homelab/token"
  type  = "SecureString"
  value = data.cloudflare_zero_trust_tunnel_cloudflared_token.homelab.token
}

resource "aws_ssm_parameter" "cloudflare_homelab_tunnel_id" {
  name  = "/homelab/cloudflare/tunnel/homelab/id"
  type  = "SecureString"
  value = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}
