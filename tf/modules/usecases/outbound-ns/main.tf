
# Shortened name of region will be added to regional resources names
locals {
  region_short = replace( replace( replace( replace(var.day0.region, "europe-", "eu"), "australia", "au" ), "northamerica", "na"), "southamerica", "sa")
}

data "google_compute_forwarding_rule" "elb" {
  name = reverse( split( "/", var.elb ))[0]
}

resource "fortios_firewall_ippool" "this" {
  name = "gcp-${var.name}-eip"
  type = "overload"
  startip = data.google_compute_forwarding_rule.elb.ip_address
  endip = data.google_compute_forwarding_rule.elb.ip_address
}

resource "fortios_firewall_policy" "allowout" {
  name = "${var.name}-allowout"
  action = "accept"
  schedule = "always"
  inspection_mode = "flow"
  status = "enable"
  utm_status = "enable"
  application_list = "default"
  av_profile = "default"
  ips_sensor = "default"
  webfilter_profile = "default"
  ssl_ssh_profile = "certificate-inspection"

  logtraffic = "all"

  srcintf {
    name = "port2"
  }
  dstintf {
    name = "port1"
  }
  srcaddr {
    name = "all"
  }
  dstaddr {
    name = "all"
  }
  service {
    name = "ALL"
  }
  nat = "enable"
  ippool = "enable"
  poolname {
    name = fortios_firewall_ippool.this.name
  }
}
