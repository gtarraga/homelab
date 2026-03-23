provider "aws" {
  region = var.aws_region
}

data "aws_ssm_parameter" "cloudflare_api_token" {
  name = "/homelab/cloudflare/terraform/token"
}

data "aws_ssm_parameter" "tailscale_api_key" {
  name = "/homelab/tailscale/terraform/api-key"
}

provider "cloudflare" {
  api_token = data.aws_ssm_parameter.cloudflare_api_token.value
}

provider "tailscale" {
  api_key = data.aws_ssm_parameter.tailscale_api_key.value
}
