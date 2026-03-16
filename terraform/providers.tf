provider "aws" {
  region = var.aws_region
}

data "aws_ssm_parameter" "cloudflare_api_token" {
  name = "/homelab/cloudflare/terraform/token"
}

provider "cloudflare" {
  api_token = data.aws_ssm_parameter.cloudflare_api_token.value
}
