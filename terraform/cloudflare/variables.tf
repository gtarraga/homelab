variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token"
  sensitive   = true
} 

variable "zone_name" {
  type    = string
  default = "stoneforge.dev"
}
