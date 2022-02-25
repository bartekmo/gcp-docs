# FortiGate reference architecture for GCP
## Deployment and management using Terraform

This repo contains terraform modules to deploy and manage FortiGate reference architecture in Google Cloud. It uses both Google Cloud as well as FortiOS providers.

The templates are split into [day0](day0/) and [day1](day1/) folders, which should be deployed as separate configurations.

* Day0 - deploys a cluster of FortiGates into GCP and connects them to 4 subnets. The subnets might be created before and their **names** be provided to the fgcp-ha-ap-lb module in `subnets` variable, or the VPCs and subnets can be created using sample-networks module as demonstrated in the code. Day0 "base" deployment does not offer any network functionality and is simply a foundation required by all Day1 modules.

* Day1 - uses a set of modules to add functionalities related to specific use-cases on top of the base day0 setup. You MUST first deploy day0 before attempting to deploy day1. You also MUST adapt day0-import.tf template file to point to your state file for day0 configuration if not using the default local backend.

### Supported use-cases

#### Protecting public services (ingress N-S inspection)

#### Secure NAT Gateway (outbound N-S inspection)

#### Segmentation for multi-tier infrastructure (E-W inspection)

#### Secure Hybrid Cloud (IPS for Interconnet)

#### Private Service Connect
