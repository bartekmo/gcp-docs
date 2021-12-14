## naming scheme:
# 1. component group name (eg. fgt, fgtilb, fgtelb, wrkld, untrust, trust)
# 2. shortened resource type (eg. vpc, sb, vm, rt, fw)
# 4. additional properties
# 5. region name if regional
# 6. a/b if primary/secondary FGT related


# I. VPCs and subnets
## Define CIDR ranges for all networks created in this deployment and save into
## variables for convenience.
CIDR_EXT=172.20.0.0/24          # untrusted network
CIDR_INT=172.20.1.0/24          # trusted network
CIDR_HASYNC=172.20.2.0/24       # FortiGate heartbeat network
CIDR_MGMT=172.20.3.0/24         # FortiGate management network (note, this can be merged with heartbeat for firmware 7.0+)
CIDR_WRKLD_PROD=10.0.0.0/16     # workload shared network - production
CIDR_WRKLD_NONPROD=10.1.0.0/16  # workload shared network - non production
CIDR_WRKLD_DEV=10.2.0.0/16      # workload shared network - development
CIDR_WRKLD=10.0.0.0/9           # all regional workload networks (supernet)
CIDR_ONPREM=192.168.0.0/16      # all on-prem networks (supernet)

## Define region and zones for deployment and save into variables for convenience
REGION=europe-west1
ZONE1=europe-west1-b
ZONE2=europe-west1-c
### Some resource names will be labeled with region or zone name. Let's use their
### shortened names:
REGION_LABEL=$(echo $REGION | tr -d '-' | sed 's/europe/eu/' | sed 's/australia/au/' | sed 's/northamerica/na/' | sed 's/southamerica/sa/' )
ZONE1_LABEL=$REGION_LABEL-${ZONE1: -1}
ZONE2_LABEL=$REGION_LABEL-${ZONE2: -1}

## Create FortiGate-connected VPC networks and subnets. Trusted VPC network will be
## restricted to a single region, other networks will be used globally.
gcloud compute networks create untrust-vpc-global \
  --subnet-mode=custom
gcloud compute networks create trust-vpc-$REGION_LABEL \
  --subnet-mode=custom
gcloud compute networks create fgt-hasync-vpc \
  --subnet-mode=custom
gcloud compute networks create fgt-mgmt-vpc \
  --subnet-mode=custom

gcloud compute networks subnets create untrust-sb-$REGION_LABEL \
  --network=untrust-vpc-global \
  --region=$REGION \
  --range=$CIDR_EXT

gcloud compute networks subnets create trust-sb-$REGION_LABEL \
  --network=trust-vpc-$REGION_LABEL \
  --region=$REGION \
  --range=$CIDR_INT

gcloud compute networks subnets create fgt-hasync-sb-$REGION_LABEL \
  --network=fgt-hasync-vpc \
  --region=$REGION \
  --range=$CIDR_HASYNC

gcloud compute networks subnets create fgt-mgmt-sb-$REGION_LABEL \
  --network=fgt-mgmt-vpc \
  --region=$REGION \
  --range=$CIDR_MGMT

## By default Google Cloud infrastructure will block all inbound connections.
## As we are deploying a next-generation firewall, we can disable that form of network
## protection by adding broad "allow all" Cloud Firewall rules to both untrusted
## and trusted networks
gcloud compute firewall-rules create untrust-to-fgt-fw-allowall \
  --direction=INGRESS \
  --network=untrust-vpc-global \
  --action=ALLOW \
  --rules=all \
  --source-ranges=0.0.0.0/0 \
  --target-tags=fgt

gcloud compute firewall-rules create trust-to-fgt-fw-allowall \
  --direction=INGRESS \
  --network=trust-vpc-$REGION_LABEL \
  --action=ALLOW \
  --rules=all \
  --source-ranges=0.0.0.0/0 \
  --target-tags=fgt

## fgt-hasync network will be used for communication between FortiGate instances,
## which needs to be explicitly allowed by Cloud Firewall.

gcloud compute firewall-rules create fgt-hasync-fw-allowall \
  --direction=INGRESS \
  --network=fgt-hasync-vpc \
  --action=ALLOW \
  --rules=all \
  --source-tags=fgt \
  --target-tags=fgt

## Management access must be allowed using a Cloud Firewall rule. It is recommended
## to adapt this rule and allow only authorized source IP ranges.

gcloud compute firewall-rules create fgt-mgmt-fw-allow-admin \
  --direction=INGRESS \
  --network=fgt-mgmt-vpc \
  --action=ALLOW \
  --rules="tcp:22,tcp:443" \
  --source-ranges=0.0.0.0/0 \
  --target-tags=fgt

## FortiGate instances will use their primary NIC (nic0) to reach out to
## FortiGuard servers for updates and license verification. As instances do not
## have public addresses associated with nic0, you need to enable access to Internet
## using Cloud NAT.

gcloud compute routers create untrust-nat-cr-$REGION_LABEL --region=$REGION \
  --network=untrust-vpc-global
gcloud compute routers nats create untrust-nat-$REGION_LABEL --region=$REGION \
  --router=untrust-nat-cr-$REGION_LABEL \
  --nat-custom-subnet-ip-ranges=untrust-sb-$REGION_LABEL \
  --auto-allocate-nat-external-ips


# II. Reserve static IP addresses
## Before creating instances and forwarding rules for this architecture
## you should reserve some static external and internal IP addresses.
## External

## External management addresses for FortiGate instances. You will not need them
## if your infrastructure allows you to connect directly to internal management
## IPs (e.g. via administrative Interconnect attachment)
gcloud compute addresses create fgt-mgmt-eip-$ZONE1_LABEL --region=$REGION
gcloud compute addresses create fgt-mgmt-eip-$ZONE2_LABEL --region=$REGION

## Internal addresses for trusted NICs and load balancer
gcloud compute addresses create fgt-ip-trust-$ZONE1_LABEL --region=$REGION \
  --subnet=trust-sb-$REGION_LABEL
gcloud compute addresses create fgt-ip-trust-$ZONE2_LABEL --region=$REGION \
  --subnet=trust-sb-$REGION_LABEL
gcloud compute addresses create fgtilb-trust-ip-$REGION_LABEL --region=$REGION \
  --subnet=trust-sb-$REGION_LABEL

## Internal addresses for untrusted NICs and load balancer
gcloud compute addresses create fgt-ip-untrust-$ZONE1_LABEL --region=$REGION \
  --subnet=untrust-sb-$REGION_LABEL
gcloud compute addresses create fgt-ip-untrust-$ZONE2_LABEL --region=$REGION \
  --subnet=untrust-sb-$REGION_LABEL
gcloud compute addresses create fgtilb-ip-untrust-$REGION_LABEL --region=$REGION \
  --subnet=untrust-sb-$REGION_LABEL

## Internal addresses for FGCP (FortiGate Clustering Protocol)
gcloud compute addresses create fgt-ip-hasync-$ZONE1_LABEL --region=$REGION \
  --subnet=fgt-hasync-sb-$REGION_LABEL
gcloud compute addresses create fgt-ip-hasync-$ZONE2_LABEL --region=$REGION \
  --subnet=fgt-hasync-sb-$REGION_LABEL

## Save some internal addresses to variables so they can be easily used later
IP_FGT_HASYNC_A=$(gcloud compute addresses describe fgt-ip-hasync-$ZONE1_LABEL --region=$REGION --format="get(address)")
IP_FGT_HASYNC_B=$(gcloud compute addresses describe fgt-ip-hasync-$ZONE2_LABEL --region=$REGION --format="get(address)")

# III. Create Fortigate instances

## Deploying FortiGate cloud architecture includes creating Google Cloud resources
## but also proper configuration of FortiGate instances. There are multiple ways to
## configure FortiGates. This guide provisions new instances with very basic
## configuration and adds more configuration later using FortiGate CLI. We believe that
## splitting configuration to architecture blocks will make it easier for the reader
## to understand the dependencies. In production environments you will however most
## likely build the complete configuration file upfront and provide it to FortiGate
## VM instances when provisioning.


## Build basic configuration including HA clustering and static IP addresses.
## Save to files for active and passive instance.
## Note that some values depend on the networks you created earlier and reserved
## private IP addresses.
cat <<EOT > metadata_active.txt
config system global
  set hostname fgt-vm-$ZONE1_LABEL
end

config system probe-response
  set mode http-probe
  set http-probe-value OK
  set port 8008
end

config system sdn-connector
  edit "gcp_conn"
  set type gcp
  next
end

config system interface
  edit port1
    set mode static
    set ip $(gcloud compute addresses describe fgt-ip-untrust-$ZONE1_LABEL --region=$REGION --format="get(address)")/32
  next
  edit port2
    set mode static
    set ip $(gcloud compute addresses describe fgt-ip-trust-$ZONE1_LABEL --region=$REGION --format="get(address)")/32
  next
  edit port3
    set mode static
    set ip $IP_FGT_HASYNC_A/32
  next
  edit port4
    set allowaccess ssh https
  next
end

config router static
  edit 1
    set gateway $(gcloud compute networks subnets describe untrust-sb-$REGION_LABEL --region=$REGION --format='get(gatewayAddress)')
    set device port1
  end
end

config system ha
  set group-name "cluster1"
  set mode a-p
  set hbdev port3 50
  set session-pickup enable
  set ha-mgmt-status enable
  config ha-mgmt-interfaces
    edit 1
    set interface port4
    set gateway $(gcloud compute networks subnets describe fgt-mgmt-sb-$REGION_LABEL --region=$REGION --format='get(gatewayAddress)')
    next
  end
  set override disable
  set priority 200
  set unicast-hb enable
  set unicast-hb-peerip $IP_FGT_HASYNC_B
  set unicast-hb-netmask 255.255.255.0
end
EOT

cat <<EOT > metadata_passive.txt
config system global
  set hostname fgt-vm-$ZONE2_LABEL
end

config system sdn-connector
  edit "gcp_conn"
  set type gcp
  next
end

config system interface
  edit port1
    set mode static
    set ip $(gcloud compute addresses describe fgt-ip-untrust-$ZONE2_LABEL --region=$REGION --format="get(address)")
  next
  edit port2
    set mode static
    set ip $(gcloud compute addresses describe fgt-ip-trust-$ZONE2_LABEL --region=$REGION --format="get(address)")
  next
  edit port3
    set mode static
    set ip $IP_FGT_HASYNC_B/32
  next
  edit port4
    set allowaccess ssh https
  next
end

config router static
  edit 1
    set gateway $(gcloud compute networks subnets describe untrust-sb-$REGION_LABEL --region=$REGION --format='get(gatewayAddress)')
    set device port1
  end
end

config system ha
  set group-name "cluster1"
  set mode a-p
  set hbdev port3 50
  set session-pickup enable
  set ha-mgmt-status enable
  config ha-mgmt-interfaces
    edit 1
    set interface port4
    set gateway $(gcloud compute networks subnets describe fgt-mgmt-sb-$REGION_LABEL --region=$REGION --format='get(gatewayAddress)')
    next
  end
  set override disable
  set priority 100
  set unicast-hb enable
  set unicast-hb-peerip $IP_FGT_HASYNC_A
  set unicast-hb-netmask 255.255.255.0
end
EOT

## FortiGate needs additional log disk to store data. You can skip adding
## log disks if your FortiGates will forward traffic data to FortiAnalyzer or FortiManager.
gcloud compute disks create fgt-logdisk-$ZONE1_LABEL --zone=$ZONE1 \
  --size=100 \
  --type=pd-ssd
gcloud compute disks create fgt-logdisk-$ZONE2_LABEL --zone=$ZONE2 \
  --size=100 \
  --type=pd-ssd

## In order to deploy VM instances you need to use base FortiGate image. Fortinet published set of images
## which can be used by any Google Cloud user in fortigcp-project-001. You can find there image for
## a specific version you want to use (the example script below selects the last BYOL image). If you do
## not need to use a specific version you can use image family to let the cloud find the newest image
## automatically.
##
## It is important to select image associated with your desired licensing (PAYG or BYOL). PAYG image names
## start with "fortinet-fgtondemand".
FGT_IMG_URL=$(gcloud compute images list --project fortigcp-project-001 --filter="name ~ fortinet-fgt- AND status:READY" --format="get(selfLink)" | sort -r | head -1)

## Licensing
## FortiGate instances in Google Cloud can be licensed in 2 different ways:
## - PAYG - the license is automatically attached to a new instance and your Billing Account
##          will be charged via Google Cloud Marketplace for every hour of the instance running.
##          This method of licensing is highly flexible and perfect for PoC phase but
##          will be expensive if your instance is running continuously.
##          Note that sustained usage discount applies only to the Google Compute Engine costs,
##          but not to the license fee.
## - BYOL - you have to provide a license purchased through Fortinet channel. BYOL licenses are
##          prepaid and available for different time periods. Flex licenses are also supported.
##          After purchase your license must be activated in Fortinet support portal and the
##          *.lic file uploaded via FortiGate web console or provided during deployment.
##          BYOL licenses are recommended for sustained use.
##          For more information on Fortinet licensing contact your local reseller or Fortinet team.

## This example uses BYOL licensing. Please copy your *.lic files to local directory as lic1.lic
## and lic2.lic before proceeding.

## Create FortiGate 4-nic instances using the image selected above.
## FortiGates will be provisioned with the basic configuration and with BYOL licenses from
## lic1.lic and lic2.lic files
## TODO: is there really no way to enable MULTI_IP_SUBNET using gcloud ??
## TODO: correct scope and service account
## TODO: switch to image family
gcloud compute instances create fgt-vm-$ZONE1_LABEL --zone=$ZONE1 \
  --machine-type=e2-standard-4 \
  --image=$FGT_IMG_URL \
  --can-ip-forward \
  --network-interface="network=untrust-vpc-global,subnet=untrust-sb-$REGION_LABEL,no-address,private-network-ip=fgt-ip-untrust-$ZONE1_LABEL" \
  --network-interface="network=trust-vpc-$REGION_LABEL,subnet=trust-sb-$REGION_LABEL,no-address,private-network-ip=fgt-ip-trust-$ZONE1_LABEL" \
  --network-interface="network=fgt-hasync-vpc,subnet=fgt-hasync-sb-$REGION_LABEL,no-address,private-network-ip=fgt-ip-hasync-$ZONE1_LABEL" \
  --network-interface="network=fgt-mgmt-vpc,subnet=fgt-mgmt-sb-$REGION_LABEL,address=fgt-mgmt-eip-$ZONE1_LABEL" \
  --disk="auto-delete=yes,boot=no,device-name=logdisk,mode=rw,name=fgt-logdisk-$ZONE1_LABEL" \
  --tags=fgt \
  --metadata-from-file="user-data=metadata_active.txt,license=lic1.lic" \
  --async

gcloud compute instances create fgt-vm-$ZONE2_LABEL --zone=$ZONE2 \
  --machine-type=e2-standard-4 \
  --image=$FGT_IMG_URL \
  --can-ip-forward \
  --network-interface="network=untrust-vpc-global,subnet=untrust-sb-$REGION_LABEL,no-address,private-network-ip=fgt-ip-untrust-$ZONE2_LABEL" \
  --network-interface="network=trust-vpc-$REGION_LABEL,subnet=trust-sb-$REGION_LABEL,no-address,private-network-ip=fgt-ip-trust-$ZONE2_LABEL" \
  --network-interface="network=fgt-hasync-vpc,subnet=fgt-hasync-sb-$REGION_LABEL,no-address,private-network-ip=fgt-ip-hasync-$ZONE2_LABEL" \
  --network-interface="network=fgt-mgmt-vpc,subnet=fgt-mgmt-sb-$REGION_LABEL,address=fgt-mgmt-eip-$ZONE2_LABEL" \
  --disk="auto-delete=yes,boot=no,device-name=logdisk,mode=rw,name=fgt-logdisk-$ZONE2_LABEL" \
  --tags=fgt \
  --metadata-from-file="user-data=metadata_passive.txt,license=lic2.lic"


## Create Unmanaged Instance Groups, which will be used by the load balancers
gcloud compute instance-groups unmanaged create fgt-umig-$ZONE1_LABEL --zone=$ZONE1
gcloud compute instance-groups unmanaged create fgt-umig-$ZONE2_LABEL --zone=$ZONE2

gcloud compute instance-groups unmanaged add-instances fgt-umig-$ZONE1_LABEL \
  --instances=fgt-vm-$ZONE1_LABEL \
  --zone=$ZONE1

gcloud compute instance-groups unmanaged add-instances fgt-umig-$ZONE2_LABEL \
  --instances=fgt-vm-$ZONE2_LABEL \
  --zone=$ZONE2

## First connection to FortiGate
## After deployment the FortiGate instances must boot, format the logdisk, verify
## and apply the license. This procedure will take couple of minutes and 2 reboots.
## You can monitor the progress using serial output. After provisioning is finished
## you will be able to log in via SSH.
## By default you can log into the active FortiGate instance as user 'admin'
## using instance id as the password.

## Find out active FortiGate instance id
gcloud compute instances describe fgt-vm-$ZONE1_LABEL --zone=$ZONE1 --format="get(id)"

## Find out (and save for later use) active FortiGate public management IP
EIP_MGMT=$(gcloud compute addresses describe fgt-mgmt-eip-$ZONE1_LABEL --region=$REGION --format="get(address)")

## Wait a moment, connect to FortiGate and configure admin password
sleep 120 && ssh admin@$EIP_MGMT

## (optional - for the smoothness of batch script)
ls ~/.ssh/id_rsa.pub && ssh admin@$EIP_MGMT "config sys admin
edit admin
set ssh-public-key1 \"$(cat ~/.ssh/id_rsa.pub)\"
next
end"

# IV. Health checks
## Create a common health check to be used for detecting active/passive instance
gcloud compute health-checks create http fgt-hcheck-tcp8008 --region=$REGION \
  --port=8008 \
  --timeout=2s \
  --healthy-threshold=1

## Health check responder also needs to be configured in FortiGate.
ssh admin@$EIP_MGMT "config system probe-response
  set mode http-probe
  set http-probe-value OK
  set port 8008
end"

## Health check considerations
## There are multiple ways to configure health checks in the type of setup
## describe in this article:
## 1. probing the backend - health checks are configured for individual services
##    available behind the firewall and are using port/protocol used by the service
##    itself. Connections are forwarded by the active FortiGate instance and
##    responded by the backend server. This method checks the full path, but
##    is confusing if the backend service breaks without failing over the firewalls
##    as the whole firewall cluster will be marked as unhealthy
## 2. probing the firewall using VIP - in this setup probe-responder is configured
##    on a dedicated loopback interface and health check connections must be
##    redirected using VIP and allowed using firewall policy. This method probes
##    availability of the firewall itself and will reliably detect HA failover,
##    but its configuration overlaps with forwarded traffic policy, which might
##    introduce confusion and cause mistakes in configuration
## 3. probing the firewall using secondary ip (recommended) - each interface
##    being target of a load balancer is configured to respond to probe connections.
##    As probes are targeted to load balancer frontend IP address, it must be defined
##    as interface's secondary ip. Also, as the probe connections are initiated
##    from public IP space (see https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges)
##    you have to add proper routes to every interfaces targeted by a load balancer.


# V. Internal Load Balancers
## Traffic is routed via FortiGates with use of Internal Load Balancers
## (see "Internal TCP/UDP load balancers as next hops"
## https://cloud.google.com/load-balancing/docs/internal/ilb-next-hop-overview)


## ILB in Trusted VPC for cloud egress traffic and E-W workload inspection
gcloud compute backend-services create fgtilb-trust-bes-$REGION_LABEL --region=$REGION \
  --network=trust-vpc-$REGION_LABEL \
  --load-balancing-scheme=INTERNAL \
  --health-checks=fgt-hcheck-tcp8008 \
  --health-checks-region=$REGION

gcloud compute backend-services add-backend fgtilb-trust-bes-$REGION_LABEL --region=$REGION \
  --instance-group=fgt-umig-$ZONE1_LABEL \
  --instance-group-zone=$ZONE1
gcloud compute backend-services add-backend fgtilb-trust-bes-$REGION_LABEL --region=$REGION\
  --instance-group=fgt-umig-$ZONE2_LABEL \
  --instance-group-zone=$ZONE2

gcloud compute forwarding-rules create fgtilb-trust-fwd-$REGION_LABEL-tcp --region=$REGION \
  --address=fgtilb-trust-ip-$REGION_LABEL \
  --ip-protocol=TCP \
  --ports=ALL \
  --load-balancing-scheme=INTERNAL \
  --backend-service=fgtilb-trust-bes-$REGION_LABEL \
  --subnet=trust-sb-$REGION_LABEL

## FortiGate config change to make it respond to health check probes on the IP address of the ILB
ssh admin@$EIP_MGMT "config system interface
edit port2
set secondary-IP enable
config secondaryip
edit 1
set ip $(gcloud compute addresses describe fgtilb-trust-ip-$REGION_LABEL --format='get(address)' --region=$REGION) 255.255.255.255
set allowaccess probe-response
next
end
next
end"

## FortiGate config to not reject connections from health checks on port2 due to RPF checks
ssh admin@$EIP_MGMT "config router static
edit 200
set dst 35.191.0.0/16
set device port2
set gateway 172.20.1.1
next
edit 201
set dst 130.211.0.0/22
set device port2
set gateway 172.20.1.1
next
end"

## ILB in Untrusted VPC for traffic from on-prem to workloads and to PSA
gcloud compute backend-services create fgtilb-untrust-bes-$REGION_LABEL --region=$REGION \
  --network=untrust-vpc-global \
  --load-balancing-scheme=INTERNAL \
  --health-checks=fgt-hcheck-tcp8008 \
  --health-checks-region=$REGION

gcloud compute backend-services add-backend fgtilb-untrust-bes-$REGION_LABEL --region=$REGION \
  --instance-group=fgt-umig-$ZONE1_LABEL \
  --instance-group-zone=$ZONE1
gcloud compute backend-services add-backend fgtilb-untrust-bes-$REGION_LABEL --region=$REGION\
  --instance-group=fgt-umig-$ZONE2_LABEL \
  --instance-group-zone=$ZONE2

gcloud compute forwarding-rules create fgtilb-untrust-fwd-$REGION_LABEL-tcp --region=$REGION \
  --address=fgtilb-ip-untrust-$REGION_LABEL \
  --ip-protocol=TCP \
  --ports=ALL \
  --load-balancing-scheme=INTERNAL \
  --backend-service=fgtilb-untrust-bes-$REGION_LABEL \
  --subnet=untrust-sb-$REGION_LABEL

## FortiGate config change to make it respond to health check probes on the IP address of the ILB
ssh admin@$EIP_MGMT "config system interface
edit port1
set secondary-IP enable
config secondaryip
edit 1
set ip $(gcloud compute addresses describe fgtilb-ip-untrust-$REGION_LABEL --format='get(address)' --region=$REGION) 255.255.255.255
set allowaccess probe-response
next
end
next
end"

## Additional route on Fortigate for health check source range is not needed, because RPF
## check is satisfied by the default route on port1

## Define route for the oubound flow from trusted zone (trusted + workloads) to Internet
gcloud compute routes create rt-trust-$REGION_LABEL-default-via-fgt \
  --network=trust-vpc-$REGION_LABEL \
  --destination-range=0.0.0.0/0 \
  --next-hop-ilb=fgtilb-trust-fwd-$REGION_LABEL-tcp \
  --next-hop-ilb-region=$REGION
## Define route for the flow from trusted cloud to on-prem
gcloud compute routes create rt-trust-$REGION_LABEL-to-onprem-via-fgt \
  --network=trust-vpc-$REGION_LABEL \
  --destination-range=$CIDR_ONPREM \
  --next-hop-ilb=fgtilb-trust-fwd-$REGION_LABEL-tcp \
  --next-hop-ilb-region=$REGION

################################################################################
#
# VI. Workload spoke VPC networks
# --------------------------------
## Deciding on granularity of workload VPC networks is a critical infrastructure decision
## because it will define the security domains visible to FortiGate firewalls. Any traffic
## inside a VPC can only be filtered using Cloud Firewall stateful rules and monitored
## by FortiGate IDS using packet mirroring. Only traffic between different workload VPCs
## can be fully inspected using and inline IPS.
##
## In this reference architecture we use 3 shared VPCs as an example, but your infrastructure
## might require more. While you can easily add more spoke VPCs later on without any
## downtime, moving workloads between VPCs (e.g. when splitting one workload VPC into two)
## is much more complicated.
## Google Cloud supports up to 25 spoke VPCs per firewall NIC. The maximum number of spokes
## is 150 (using 6 FortiGate network interfaces for trusted VPCs).

## Create workload VPC networks
gcloud compute networks create wrkld-prod-vpc-$REGION_LABEL \
  --subnet-mode=custom
gcloud compute networks create wrkld-nonprod-vpc-$REGION_LABEL \
  --subnet-mode=custom
gcloud compute networks create wrkld-dev-vpc-$REGION_LABEL \
  --subnet-mode=custom

## It is recommended to delete existing default routes from spoke networks as they might interfere with
## imported custom routes.
gcloud compute routes delete `gcloud compute routes list --filter="network=wrkld-prod-vpc-$REGION_LABEL destRange=0.0.0.0/0" --format="get(name)"` -q
gcloud compute routes delete `gcloud compute routes list --filter="network=wrkld-nonprod-vpc-$REGION_LABEL destRange=0.0.0.0/0" --format="get(name)"` -q
gcloud compute routes delete `gcloud compute routes list --filter="network=wrkld-dev-vpc-$REGION_LABEL destRange=0.0.0.0/0" --format="get(name)"` -q

## Create workload subnets
gcloud compute networks subnets create wrkld-prod-sb-$REGION_LABEL --region=$REGION \
  --network=wrkld-prod-vpc-$REGION_LABEL \
  --range=$CIDR_WRKLD_PROD

gcloud compute networks subnets create wrkld-nonprod-sb-$REGION_LABEL --region=$REGION \
  --network=wrkld-nonprod-vpc-$REGION_LABEL \
  --range=$CIDR_WRKLD_NONPROD

gcloud compute networks subnets create wrkld-dev-sb-$REGION_LABEL --region=$REGION \
  --network=wrkld-dev-vpc-$REGION_LABEL \
  --range=$CIDR_WRKLD_DEV

################################################################################
#
# VII. Peering workloads to trusted VPC network
# ---------------------------------------------
## Each workload VPC (spoke) needs to be peered with the Trusted VPC (hub) to enable
## traffic flow to, from and between spoke networks. To simplify route management,
## in single-region deployments and in deployments using regional workload VPCs
## peerings should export routes from hub and import them into spoke VPCs.
##
gcloud compute networks peerings create wrkld-peer-hub-to-prod-$REGION_LABEL --network=trust-vpc-$REGION_LABEL \
  --peer-network=wrkld-prod-vpc-$REGION_LABEL \
  --export-custom-routes
gcloud compute networks peerings create wrkld-peer-prod-to-hub-$REGION_LABEL --network=wrkld-prod-vpc-$REGION_LABEL \
  --peer-network=trust-vpc-$REGION_LABEL \
  --import-custom-routes

gcloud compute networks peerings create wrkld-peer-hub-to-nonprod-$REGION_LABEL --network=trust-vpc-$REGION_LABEL \
  --peer-network=wrkld-nonprod-vpc-$REGION_LABEL \
  --export-custom-routes
gcloud compute networks peerings create wrkld-peer-nonprod-to-hub-$REGION_LABEL --network=wrkld-nonprod-vpc-$REGION_LABEL \
  --peer-network=trust-vpc-$REGION_LABEL \
  --import-custom-routes

gcloud compute networks peerings create wrkld-peer-dev-to-hub-$REGION_LABEL --network=wrkld-dev-vpc-$REGION_LABEL \
  --peer-network=trust-vpc-$REGION_LABEL \
  --import-custom-routes
gcloud compute networks peerings create wrkld-peer-hub-to-dev-$REGION_LABEL --network=trust-vpc-$REGION_LABEL \
  --peer-network=wrkld-dev-vpc-$REGION_LABEL \
  --export-custom-routes

## For each peering a set of routes must be created for the traffic flow:
## - from FortiGate to spoke VPC
## - from on-prem to spoke VPC
## - from other spokes to spoke VPC and from Private Service Access peering to spoke VPC
##
## All those routes for individual spokes can be replaced by a single set of routes towards
## a supernet covering all spoke VPCs in a given region if you're using 'supernetable'
## address ranges for all spoke (workload) VPCs.
##
## If you're not using Private Service Connection the trust-to-wrkld route is redundant
## with the trust-to-internet route created earkier and can be skipped.
##
## When using IaC templating tool like Terraform, you might consider creating a module
## to automatically create peerings and routes for each spoke VPC.

ssh admin@$EIP_MGMT "config router static
edit 100
set dst $CIDR_WRKLD
set device port2
set gateway $(gcloud compute networks subnets describe trust-sb-$REGION_LABEL --region=$REGION --format="get(gatewayAddress)")
next
end"

gcloud compute routes create rt-untrust-to-wrkld-$REGION_LABEL-via-fgt \
  --network=untrust-vpc-global \
  --destination-range=$CIDR_WRKLD \
  --next-hop-ilb=fgtilb-untrust-fwd-$REGION_LABEL-tcp \
  --next-hop-ilb-region=$REGION

gcloud compute routes create rt-trust-to-wrkld-$REGION_LABEL-via-fgt \
  --network=trust-vpc-$REGION_LABEL \
  --destination-range=$CIDR_WRKLD \
  --next-hop-ilb=fgtilb-trust-fwd-$REGION_LABEL-tcp \
  --next-hop-ilb-region=$REGION

## In this example address ranges of all spokes are aggregated into $CIDR_WRKLD, so only
## one set of routes is needed for all workload networks.

################################################################################
#
# VIII. External Load Balancer
# ----------------------------
## Inbound connections from Internet can be redirected to public services and
## protected by FortiGate's threat protection features. To direct the traffic
## via active FortiGate instance you can use External Load Balancer. This method
## supports multiple public IPs and fast failover times.
##
## The example below leverages new L3_DEFAULT protocol, which allows to use
## only a single forwarding rule for all protocols. If your deployment requires
## GA support level and L3_DEFAULT is still in preview, use separate forwarding
## rules for TCP and UDP and configure a target pool instead of backend service.

## External IP to publish services to Internet. You can use more if you're
## publishing more services requiring separate IP addresses
gcloud compute addresses create fgtelb-serv1-eip-$REGION_LABEL --region=$REGION

gcloud beta compute backend-services create fgtelb-bes-$REGION_LABEL --region=$REGION \
  --load-balancing-scheme=EXTERNAL \
  --protocol=UNSPECIFIED \
  --health-checks=fgt-hcheck-tcp8008 \
  --health-checks-region=$REGION

gcloud compute backend-services add-backend fgtelb-bes-$REGION_LABEL --region=$REGION \
  --instance-group=fgt-umig-$ZONE1_LABEL \
  --instance-group-zone=$ZONE1
gcloud compute backend-services add-backend fgtelb-bes-$REGION_LABEL --region=$REGION\
  --instance-group=fgt-umig-$ZONE2_LABEL \
  --instance-group-zone=$ZONE2

gcloud beta compute forwarding-rules create fgtelb-serv1-fwd-$REGION_LABEL-l3 --region=$REGION \
  --address=fgtelb-serv1-eip-$REGION_LABEL \
  --ip-protocol=L3_DEFAULT \
  --ports=ALL \
  --load-balancing-scheme=EXTERNAL \
  --backend-service=fgtelb-bes-$REGION_LABEL

## Enable probe responder for this load balancer on secondaryip of port1
ssh admin@$EIP_MGMT "config system interface
edit port1
set secondary-IP enable
config secondaryip
edit 11
set ip $(gcloud compute addresses describe untrust-serv1-eip-$REGION_LABEL --format='get(address)' --region=$REGION) 255.255.255.255
set allowaccess probe-response
next
end
next
end"
