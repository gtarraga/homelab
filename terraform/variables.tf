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

variable "root_domain" {
  type    = string
  default = "stoneforge.dev"
}

variable "tailscale_nameserver_tag" {
  type    = string
  default = "tag:homelab-dns"
}