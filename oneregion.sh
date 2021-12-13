## naming scheme:
# 1. component group name (eg. fgt, fgtilb, fgtelb, wrkld, untrust, trust)
# 2. shortened resource type (eg. vpc, sb, vm, rt, fw)
# 4. additional properties
# 5. region name if regional
# 6. a/b if primary/secondary FGT related


# VPCs and subnets
CIDR_EXT=172.20.0.0/24
CIDR_INT=172.20.1.0/24
CIDR_HASYNC=172.20.2.0/24
CIDR_MGMT=172.20.3.0/24
CIDR_WRKLD_PROD=10.0.0.0/16
CIDR_WRKLD_NONPROD=10.1.0.0/16
CIDR_WRKLD_DEV=10.2.0.0/16
CIDR_ONPREM=192.168.0.0/16

# Region and zones
REGION=europe-west1
ZONE1=europe-west1-b
ZONE2=europe-west1-c
#REGION_LABEL=euwest1
#ZONE1_LABEL=euwest1-b
#ZONE2_LABEL=euwest1-c
REGION_LABEL=$(echo $REGION | tr -d '-' | sed 's/europe/eu/' | sed 's/australia/au/' | sed 's/northamerica/na/' | sed 's/southamerica/sa/' )
ZONE1_LABEL=$REGION_LABEL-${ZONE1: -1}
ZONE2_LABEL=$REGION_LABEL-${ZONE2: -1}

## FortiGate-connected VPC networks
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

## enable access in networks
gcloud compute firewall-rules create fgt-hasync-fw-allowall \
  --direction=INGRESS \
  --network=fgt-hasync-vpc \
  --action=ALLOW \
  --rules=all \
  --source-tags=fgt \
  --target-tags=fgt

gcloud compute firewall-rules create fgt-mgmt-fw-allow-admin \
  --direction=INGRESS \
  --network=fgt-mgmt-vpc \
  --action=ALLOW \
  --rules="tcp:22,tcp:443" \
  --source-ranges=0.0.0.0/0 \
  --target-tags=fgt

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


gcloud compute routers create untrust-nat-cr-$REGION_LABEL --region=$REGION \
  --network=untrust-vpc-global
gcloud compute routers nats create untrust-nat-$REGION_LABEL --region=$REGION \
  --router=untrust-nat-cr-$REGION_LABEL \
  --nat-custom-subnet-ip-ranges=untrust-sb-$REGION_LABEL \
  --auto-allocate-nat-external-ips


## workload spoke VPC networks
gcloud compute networks create wrkld-prod-vpc-$REGION_LABEL \
  --subnet-mode=custom
gcloud compute networks create wrkld-nonprod-vpc-$REGION_LABEL \
  --subnet-mode=custom
gcloud compute networks create wrkld-dev-vpc-$REGION_LABEL \
  --subnet-mode=custom

gcloud compute networks subnets create wrkld-prod-sb-$REGION_LABEL --region=$REGION \
  --network=wrkld-prod-vpc-$REGION_LABEL \
  --range=$CIDR_WRKLD_PROD

gcloud compute networks subnets create wrkld-nonprod-sb-$REGION_LABEL --region=$REGION \
  --network=wrkld-nonprod-vpc-$REGION_LABEL \
  --range=$CIDR_WRKLD_NONPROD

gcloud compute networks subnets create wrkld-dev-sb-$REGION_LABEL --region=$REGION \
  --network=wrkld-dev-vpc-$REGION_LABEL \
  --range=$CIDR_WRKLD_DEV

### delete existing default routes
gcloud compute routes delete `gcloud compute routes list --filter="network=wrkld-prod-vpc-$REGION_LABEL destRange=0.0.0.0/0" --format="get(name)"` -q
gcloud compute routes delete `gcloud compute routes list --filter="network=wrkld-nonprod-vpc-$REGION_LABEL destRange=0.0.0.0/0" --format="get(name)"` -q
gcloud compute routes delete `gcloud compute routes list --filter="network=wrkld-dev-vpc-$REGION_LABEL destRange=0.0.0.0/0" --format="get(name)"` -q

# Create static IP addresses
## External
gcloud compute addresses create untrust-serv1-eip-$REGION_LABEL --region=$REGION
gcloud compute addresses create fgt-mgmt-eip-$ZONE1_LABEL --region=$REGION
gcloud compute addresses create fgt-mgmt-eip-$ZONE2_LABEL --region=$REGION

## Internal
gcloud compute addresses create fgt-ip-trust-$ZONE1_LABEL --region=$REGION \
  --subnet=trust-sb-$REGION_LABEL
gcloud compute addresses create fgt-ip-trust-$ZONE2_LABEL --region=$REGION \
  --subnet=trust-sb-$REGION_LABEL
gcloud compute addresses create fgtilb-trust-ip-$REGION_LABEL --region=$REGION \
  --subnet=trust-sb-$REGION_LABEL

gcloud compute addresses create fgt-ip-untrust-$ZONE1_LABEL --region=$REGION \
  --subnet=untrust-sb-$REGION_LABEL
gcloud compute addresses create fgt-ip-untrust-$ZONE2_LABEL --region=$REGION \
  --subnet=untrust-sb-$REGION_LABEL
gcloud compute addresses create fgtilb-ip-untrust-$REGION_LABEL --region=$REGION \
  --subnet=untrust-sb-$REGION_LABEL

gcloud compute addresses create fgt-ip-hasync-$ZONE1_LABEL --region=$REGION \
  --subnet=fgt-hasync-sb-$REGION_LABEL
gcloud compute addresses create fgt-ip-hasync-$ZONE2_LABEL --region=$REGION \
  --subnet=fgt-hasync-sb-$REGION_LABEL

# Create Fortigate instances
FGT_IMG_URL=$(gcloud compute images list --project fortigcp-project-001 --filter="name ~ fortinet-fgt- AND status:READY" --format="get(selfLink)" | sort -r | head -1)

## save internal addresses to variables and prepare basic configs for FGCP
IP_FGT_HASYNC_A=$(gcloud compute addresses describe fgt-ip-hasync-$ZONE1_LABEL --region=$REGION --format="get(address)")
IP_FGT_HASYNC_B=$(gcloud compute addresses describe fgt-ip-hasync-$ZONE2_LABEL --region=$REGION --format="get(address)")
EIP_MGMT=$(gcloud compute addresses describe fgt-mgmt-eip-$ZONE1_LABEL --region=$REGION --format="get(address)")

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
    set gateway 172.20.0.1
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
    set gateway 172.20.3.1
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
    set gateway 172.20.0.1
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
    set gateway 172.20.3.1
    next
  end
  set override disable
  set priority 100
  set unicast-hb enable
  set unicast-hb-peerip $IP_FGT_HASYNC_A
  set unicast-hb-netmask 255.255.255.0
end
EOT

## create log disks
gcloud compute disks create fgt-logdisk-$ZONE1_LABEL --zone=$ZONE1 \
  --size=100 \
  --type=pd-ssd
gcloud compute disks create fgt-logdisk-$ZONE2_LABEL --zone=$ZONE2 \
  --size=100 \
  --type=pd-ssd

## create instances
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



## add instances to UMIGs
gcloud compute instance-groups unmanaged create fgt-umig-$ZONE1_LABEL --zone=$ZONE1
gcloud compute instance-groups unmanaged create fgt-umig-$ZONE2_LABEL --zone=$ZONE2

gcloud compute instance-groups unmanaged add-instances fgt-umig-$ZONE1_LABEL \
  --instances=fgt-vm-$ZONE1_LABEL \
  --zone=$ZONE1

gcloud compute instance-groups unmanaged add-instances fgt-umig-$ZONE2_LABEL \
  --instances=fgt-vm-$ZONE2_LABEL \
  --zone=$ZONE2

# ILB Internal
## health check
gcloud compute health-checks create http fgt-hcheck-tcp8008 --region=$REGION \
  --port=8008 \
  --timeout=2s \
  --healthy-threshold=1

## port2 ILB
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

gcloud compute routes create rt-wrkld-$REGION_LABEL-to-onprem-via-fgt \
  --network=trust-vpc-$REGION_LABEL \
  --destination-range=$CIDR_ONPREM \
  --next-hop-ilb=fgtilb-trust-fwd-$REGION_LABEL-tcp \
  --next-hop-ilb-region=$REGION
gcloud compute routes create rt-wrkld-$REGION_LABEL-default-via-fgt \
  --network=trust-vpc-$REGION_LABEL \
  --destination-range=0.0.0.0/0 \
  --next-hop-ilb=fgtilb-trust-fwd-$REGION_LABEL-tcp \
  --next-hop-ilb-region=$REGION

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

## port1 ILB
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

gcloud compute routes create rt-untrust-to-wrkld-$REGION_LABEL-via-fgt \
  --network=untrust-vpc-global \
  --destination-range=10.0.0.0/9 \
  --next-hop-ilb=fgtilb-untrust-fwd-$REGION_LABEL-tcp \
  --next-hop-ilb-region=$REGION

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

## port1 ELB
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
  --address=untrust-serv1-eip-$REGION_LABEL \
  --ip-protocol=L3_DEFAULT \
  --ports=ALL \
  --load-balancing-scheme=EXTERNAL \
  --backend-service=fgtelb-bes-$REGION_LABEL

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

# TODO: Peering
gcloud compute networks peerings create wrkld-peer-hub-to-prod-$REGION_LABEL --network=trust-vpc-$REGION_LABEL \
  --peer-network=wrkld-prod-vpc-$REGION_LABEL \
  --export-custom-routes

gcloud compute networks peerings create wrkld-peer-hub-to-nonprod-$REGION_LABEL --network=trust-vpc-$REGION_LABEL \
  --peer-network=wrkld-nonprod-vpc-$REGION_LABEL \
  --export-custom-routes

gcloud compute networks peerings create wrkld-peer-hub-to-dev-$REGION_LABEL --network=trust-vpc-$REGION_LABEL \
  --peer-network=wrkld-dev-vpc-$REGION_LABEL \
  --export-custom-routes

gcloud compute networks peerings create wrkld-peer-prod-to-hub-$REGION_LABEL --network=wrkld-prod-vpc-$REGION_LABEL \
  --peer-network=trust-vpc-$REGION_LABEL \
  --import-custom-routes

gcloud compute networks peerings create wrkld-peer-nonprod-to-hub-$REGION_LABEL --network=wrkld-nonprod-vpc-$REGION_LABEL \
  --peer-network=trust-vpc-$REGION_LABEL \
  --import-custom-routes

gcloud compute networks peerings create wrkld-peer-dev-to-hub-$REGION_LABEL --network=wrkld-dev-vpc-$REGION_LABEL \
  --peer-network=trust-vpc-$REGION_LABEL \
  --import-custom-routes
