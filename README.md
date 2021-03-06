# Ref architecture for GCP work-in-progress

## How to
### Prerequisites
- enable APIs
- copy or link FortiGate license files (.lic) to local dir as lic1.lic and lic2.lic - they are referenced when deploying instances for seamless BYOL provisioning
- preferably use an empty project, resource names used are hardly unique

## Deployment with gcloud
### create
Edit oneregion.sh to change region/zones and simply run it.
CIDRs can be changed by modifying variables at the beginning of the script.

### destroy
1. run makedestroy script to scan the oneregion.sh for used resource names and generate oneregion-destroy.sh script
1. run oneregion-destroy.sh

## Deployment with Deployment Manager
#### Empty infra
```
gcloud deployment-manager deployments create ftnt-ref-empty --config config.yaml
```

### Single region with sample workloads
Note: requires enabling DNS API as workloads make use of DNS peering
```
gcloud deployment-manager deployments create ftnt-ref-single --config 1region-with-servers.yaml
```

### High-level overview for a single region
![single region high-level overview](https://lucid.app/publicSegments/view/076586e7-f57f-4117-8a64-4b41810d3bc3/image.png)

### Dual-region for IC 99.99 SLA
![dual-region overview](https://lucid.app/publicSegments/view/2751d18e-7510-4a8a-b6e4-0404041ee168/image.png)

### Detailed single-region arch
![detailed single-region diagram](https://lucid.app/publicSegments/view/d7cee608-1f55-4567-b50e-a52878903f52/image.png)

## Use-cases

### Secure Published Services
Enforcing North-South inspection is important for publishing services to the public Internet securely. All inbound connections will be first handled by the FortiGate Next-Gen Firewall for inspection before forwarding to the proper backend service. FortiGate VM can detect plenthora of attacks against various protocols using built-in IPS and AV profiles as well as restrict access based on geo location, IP addresses or FQDN.

#### Connection flow
Connections are initiated from public Internet against one of external IP addresses of External Load Balancer. Thanks to the health check the ELB forwarding rule selects the currently active FortiGate instance to forward the connection to its untrusted network interface. FortiGate uses VIP address configuration to perform Destination NAT and a firewall policy to apply inspection profiles and access rules. Connection is further forwarded using the trusted interface and delivered to the destination workload via VPC peering. The return packet is routed from workload VPC using an imported custom static route towards internal load balancer fronting the FortiGate cluster and delivered to active instance trusted interface to be NATted back and sent back to the client over untrusted interface.


### Secure Internet Gateway
Outbound connections generated by cloud workloads towards Internet should be verified against access list and inspected for malicious content. FortiGate instances can apply access policies based on VM instances or K8S metadata and apply precise policies based on destination services and applications.

#### Connection flow
Connection initiated by workload VM instance is routed using a custom static route imported from trusted VPC via VPC peering. Internal load balancer forwarding rule being the next hop uses health check to select currently active FortiGate instance and forwards the packet to its trusted interface. FortiGate uses firewall policy to apply required access checks and inspection profiles and performs source NAT to the public IP address of selected ELB forwarding rule. SNAT to ELB external IP address allows precise control over the public address used for the connection. Return packets are forwarded by ELB to FortiGate and NATted back according to session table entry.


### Secure Hybrid Cloud
[Solution Brief](https://www.fortinet.com/content/dam/fortinet/assets/solution-guides/sb-secure-hybrid-cloud.pdf)

### Security Services Hub
[Solution Brief](https://www.fortinet.com/content/dam/fortinet/assets/solution-guides/sb-fortinet-cloud-security-service-hub.pdf)
