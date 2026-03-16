module "aws_identity" {
  source       = "./modules/aws-identity"
  github_owner = var.github_owner
  github_repo  = var.github_repo
}

module "aws_ssm" {
  source = "./modules/aws-ssm"
}

module "cloudflare" {
  source = "./modules/cloudflare"
}
