variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
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
