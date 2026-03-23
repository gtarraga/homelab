data "tailscale_devices" "nameservers" {
  filter {
    name   = "tags"
    values = [var.tailscale_nameserver_tag]
  }
}

locals {
  nameserver_device = one(data.tailscale_devices.nameservers.devices)
  nameserver_ipv4 = one([
    for address in local.nameserver_device.addresses : address
    if startswith(address, "100.")
  ])
}

resource "tailscale_dns_split_nameservers" "stoneforge" {
  domain      = var.root_domain
  nameservers = [local.nameserver_ipv4]
}
