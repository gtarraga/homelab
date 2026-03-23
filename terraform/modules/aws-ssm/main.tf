resource "aws_ssm_parameter" "cf_externaldns_token" {
  name  = "/homelab/cloudflare/externaldns/token"
  type  = "SecureString"
  value = "bootstrap-replace-me"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "cf_terraform_token" {
  name  = "/homelab/cloudflare/terraform/token"
  type  = "SecureString"
  value = "bootstrap-replace-me"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "tailscale_terraform_api_key" {
  name  = "/homelab/tailscale/terraform/api-key"
  type  = "SecureString"
  value = "bootstrap-replace-me"

  lifecycle {
    ignore_changes = [value]
  }
}
