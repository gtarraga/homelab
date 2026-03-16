variable "aws_region" {
  type    = string
  default = "eu-west-1"
}
variable "github_owner" {
  type    = string
  default = "gtarraga"
}
variable "github_repo" {
  type    = string
  default = "homelab"
}
variable "github_branch" {
  type    = string
  default = "main"
}
variable "role_name" {
  type    = string
  default = "github-homelab-terraform"
}
variable "ssm_path_prefix" {
  type    = string
  default = "/homelab/"
}