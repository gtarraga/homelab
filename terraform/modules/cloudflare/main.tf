data "cloudflare_zone" "stoneforge" {
  filter = {
    name = var.zone_name
  }
}

resource "cloudflare_dns_record" "tf_probe" {
  zone_id = data.cloudflare_zone.stoneforge.id
  name    = "tf-probe"
  type    = "TXT"
  content = "terraform-provisioned"
  ttl     = 300
  proxied = false
}
