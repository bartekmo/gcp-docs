# Create base deployment of FortiGate HA cluster
module "fortigates" {
  source        = "../modules/fgcp-ha-ap-lb"

  prefix        = "bmlog-"
  region        = "europe-west2"
  license_files = [
    "../../lic1.lic",
    "../../lic2.lic"
  ]

  # Remember to pass subnet list as names. No selfLinks
  subnets       = [
    "bm-log-ext-sb",
    "bm-int-sb",
    "bm-hasync-log-sb",
    "bm-mgmt-log-sb"
  ]
}
