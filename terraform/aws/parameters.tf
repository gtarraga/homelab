resource "aws_ssm_parameter" "cf_externaldns_token" {
  name  = "/homelab/cloudflare/externaldns/token"
  type  = "SecureString"
  value = "bootstrap-replace-me" # This gets replaced by the actual token via aws ssm put-parameter
}

resource "aws_ssm_parameter" "cf_terraform_token" {
  name  = "/homelab/cloudflare/terraform/token"
  type  = "SecureString"
  value = "bootstrap-replace-me" # This gets replaced by the actual token via aws ssm put-parameter
}