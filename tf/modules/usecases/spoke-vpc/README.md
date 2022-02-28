# FortiGate Reference Architecture: Use-cases
# Segmentation for multi-tier infrastructure (E-W inspection)

East-west inspection in GCP can be provided only for traffic between VPC Networks (not inside a network), thus each security zone needs to be created as a separate VPC. Traffic between all workload VPCs properly peered to the FortiGate trusted VPC will be inspected by FortiGate VMs.

**NOTE: VPC peerings are limited by per-project quota and by platform limits of peering group size. Make sure your design fits within both limits and consult Google and Fortinet teams of your needs are larger.**

## Design & flow
![East-west traffic flow overview](https://lucid.app/publicSegments/view/dce9b998-146c-461f-afdd-0184cba2bb21/image.png)
1. Workload in a spoke VPC initiates traffic towards workload in another spoke VPC
2. Thanks to 0.0.0.0/0 route imported from trusted VPC traffic is routed over peering
3. ILB forwards the traffic to FortiGate for inspection
4. FortiGate inspects and passes the packet back to trusted VPC
5. Connection matches trusted VPC peered subnet route and gets delivered over VPC peering to destination VPC

## How to deploy
Routing between spoke VPCs relies on the default (0.0.0.0/0) custom route already added to the trusted VPC by the base (day0) deployment. All properly peered VPC Networks will pass traffic via FortiGate (unless also peered directly with destination network). To enable east-west scanning use the [spoke-vpc](modules/usecases/spoke-vpc) module for creating peerings.

This module does not create firewall policies - you have to make sure the traffic is allowed on the firewall yourself.

Note: due to GCP limitations on parallel peering operations you might encounter errors when deploying this module as for the clarity of code it limits explicit depends_on arguments. If you encounter any errors just try again.
