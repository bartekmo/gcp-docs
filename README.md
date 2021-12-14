# Ref architecture for GCP work-in-progress

## How to
### Prerequisites
- enable APIs
- copy or link FortiGate license files (.lic) to local dir as lic1.lic and lic2.lic - they are referenced when deploying instances for seamless BYOL provisioning
- preferably use an empty project, resource names used are hardly unique

### create
Edit oneregion.sh to change region/zones and simply run it. Changing of CIDRs is currently not supported

### destroy
1. run makedestroy script to scan the oneregion.sh for used resource names and generate oneregion-destroy.sh script
1. run oneregion-destroy.sh

### High-level overview for a single region
![single region high-level overview](https://lucid.app/publicSegments/view/076586e7-f57f-4117-8a64-4b41810d3bc3/image.png)

### Dual-region for IC 99.99 SLA
![dual-region overview](https://lucid.app/publicSegments/view/2751d18e-7510-4a8a-b6e4-0404041ee168/image.png)

### Detailed single-region arch
(legacy ELB)
![detailed single-region diagram](https://lucid.app/publicSegments/view/d7cee608-1f55-4567-b50e-a52878903f52/image.png)
