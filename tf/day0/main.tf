# Create set of sample networks and subnets

module "sample_networks" {
  source = "../modules/sample-networks"

  prefix = var.prefix
  region = var.GCE_REGION
  networks = ["external", "internal", "hasync", "mgmt"]
}

# Create base deployment of FortiGate HA cluster
module "fortigates" {
  source = "../modules/fgcp-ha-ap-lb"

  prefix = var.prefix
  region = var.GCE_REGION
  license_files = ["../../lic1.lic", "../../lic2.lic"]
  # Remember to pass subnet list as names. No selfLinks
  subnets = ["${var.prefix}sb-external", "${var.prefix}sb-internal", "${var.prefix}sb-hasync", "${var.prefix}sb-mgmt"]

# If creating sample VPC Networks in the same configuration - wait for them to be created!
  depends_on = [
    module.sample_networks
  ]
}
