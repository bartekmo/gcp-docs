## naming scheme:
# 1. shortened resource type (eg. vpc, sb, vm, rt, fw)
# 2. component group name (eg. fgt, fgtilb, fgtelb, wrkld)
# 3. vpc name if vpc related
# 4. additional labels
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

# Region and zones
REGION=europe-west1
ZONE1=europe-west1-b
ZONE2=europe-west1-c
#REGION_LABEL=euwest1
#ZONE1_LABEL=euwest1-b
#ZONE2_LABEL=euwest1-c
REGION_LABEL=$(echo $REGION | tr -d '-' | sed 's/europe/eu/' | sed 's/australia/au/' | sed 's/northamerica/na/' | sed 's/southamerica/sa' )
ZONE1_LABEL=$REGION_LABEL-${ZONE1: -1}
ZONE2_LABEL=$REGION_LABEL-${ZONE2: -1}

## FortiGate-connected VPC networks
gcloud compute networks create vpc-external \
  --subnet-mode=custom
gcloud compute networks create vpc-internal-$REGION_LABEL \
  --subnet-mode=custom
gcloud compute networks create vpc-fgt-hasync \
  --subnet-mode=custom
gcloud compute networks create vpc-fgt-mgmt \
  --subnet-mode=custom

gcloud compute networks subnets create sb-ext-$REGION_LABEL \
  --network=vpc-external \
  --region=$REGION \
  --range=$CIDR_EXT

gcloud compute networks subnets create sb-int-$REGION_LABEL \
  --network=vpc-internal-$REGION_LABEL \
  --region=$REGION \
  --range=$CIDR_INT

gcloud compute networks subnets create sb-fgt-hasync-$REGION_LABEL \
  --network=vpc-fgt-hasync \
  --region=$REGION \
  --range=$CIDR_HASYNC

gcloud compute networks subnets create sb-fgt-mgmt-$REGION_LABEL \
  --network=vpc-fgt-mgmt \
  --region=$REGION \
  --range=$CIDR_MGMT

## workload spoke VPC networks
gcloud compute networks create vpc-wrkld-p \
  --subnet-mode=custom
gcloud compute networks create vpc-wrkld-n \
  --subnet-mode=custom
gcloud compute networks create vpc-wrkld-d \
  --subnet-mode=custom

gcloud compute networks subnets create sb-wrkld-p-$REGION_LABEL --region=$REGION \
  --network=vpc-wrkld-p \
  --range=$CIDR_WRKLD_PROD

gcloud compute networks subnets create sb-wrkld-n-$REGION_LABEL --region=$REGION \
  --network=vpc-wrkld-n \
  --range=$CIDR_WRKLD_NONPROD

gcloud compute networks subnets create sb-wrkld-d-$REGION_LABEL --region=$REGION \
  --network=vpc-wrkld-d \
  --range=$CIDR_WRKLD_DEV



# Create static IP addresses
## External
gcloud compute addresses create eip-serv1-$REGION_LABEL --region=$REGION
gcloud compute addresses create eip-fgt-mgmt-$ZONE1_LABEL --region=$REGION
gcloud compute addresses create eip-fgt-mgmt-$ZONE2_LABEL --region=$REGION

## Internal
gcloud compute addresses create ip-fgt-int-$ZONE1_LABEL --region=$REGION \
  --subnet=sb-int-$REGION_LABEL
gcloud compute addresses create ip-fgt-int-$ZONE2_LABEL --region=$REGION \
  --subnet=sb-int-$REGION_LABEL
gcloud compute addresses create ip-fgtilb-int-$REGION_LABEL --region=$REGION \
  --subnet=sb-int-$REGION_LABEL

gcloud compute addresses create ip-fgt-ext-$ZONE1_LABEL --region=$REGION \
  --subnet=sb-ext-$REGION_LABEL
gcloud compute addresses create ip-fgt-ext-$ZONE2_LABEL --region=$REGION \
  --subnet=sb-ext-$REGION_LABEL
gcloud compute addresses create ip-fgtilb-ext-$REGION_LABEL --region=$REGION \
  --subnet=sb-ext-$REGION_LABEL

gcloud compute addresses create ip-fgt-hasync-$ZONE1_LABEL --region=$REGION \
  --subnet=sb-fgt-hasync-$REGION_LABEL
gcloud compute addresses create ip-fgt-hasync-$ZONE2_LABEL --region=$REGION \
  --subnet=sb-fgt-hasync-$REGION_LABEL

# Create Fortigate instances
FGT_IMG_URL=$(gcloud compute images list --project fortigcp-project-001 --filter="name ~ fortinet-fgt- AND status:READY" --format="get(selfLink)" | sort -r | head -1)

## save internal addresses to variables and prepare basic configs for FGCP
IP_FGT_HASYNC_A=$(gcloud compute addresses describe ip-fgt-hasync-$ZONE1_LABEL --region=$REGION --format="get(address)")
IP_FGT_HASYNC_B=$(gcloud compute addresses describe ip-fgt-hasync-$ZONE2_LABEL --region=$REGION --format="get(address)")
EIP_MGMT=$(gcloud compute addresses describe eip-fgt-mgmt-$ZONE1_LABEL --region=$REGION --format="get(address)")

cat <<EOT > metadata_active.txt
config system global
  set hostname vm-fgt-$ZONE1_LABEL
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
    set ip $(gcloud compute addresses describe ip-fgt-ext-$ZONE1_LABEL --region=$REGION --format="get(address)")/32
  next
  edit port2
    set mode static
    set ip $(gcloud compute addresses describe ip-fgt-int-$ZONE1_LABEL --region=$REGION --format="get(address)")/32
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
  set hostname vm-fgt-$ZONE2_LABEL
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
    set ip $(gcloud compute addresses describe ip-fgt-ext-$ZONE2_LABEL --region=$REGION --format="get(address)")
  next
  edit port2
    set mode static
    set ip $(gcloud compute addresses describe ip-fgt-int-$ZONE2_LABEL --region=$REGION --format="get(address)")
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
gcloud compute disks create disk-fgt-logdisk-$ZONE1_LABEL --zone=$ZONE1 \
  --size=100 \
  --type=pd-ssd
gcloud compute disks create disk-fgt-logdisk-$ZONE2_LABEL --zone=$ZONE2 \
  --size=100 \
  --type=pd-ssd

## create instances
## TODO: is there really no way to enable MULTI_IP_SUBNET using gcloud ??
## TODO: correct scope and service account
## TODO: switch to image family
gcloud compute instances create vm-fgt-$ZONE1_LABEL --zone=$ZONE1 \
  --machine-type=e2-standard-4 \
  --image=$FGT_IMG_URL \
  --can-ip-forward \
  --network-interface="network=vpc-external,subnet=sb-ext-$REGION_LABEL,no-address,private-network-ip=ip-fgt-ext-$ZONE1_LABEL" \
  --network-interface="network=vpc-internal-$REGION_LABEL,subnet=sb-int-$REGION_LABEL,no-address,private-network-ip=ip-fgt-int-$ZONE1_LABEL" \
  --network-interface="network=vpc-fgt-hasync,subnet=sb-fgt-hasync-$REGION_LABEL,no-address,private-network-ip=ip-fgt-hasync-$ZONE1_LABEL" \
  --network-interface="network=vpc-fgt-mgmt,subnet=sb-fgt-mgmt-$REGION_LABEL,address=eip-fgt-mgmt-$ZONE1_LABEL" \
  --disk="auto-delete=yes,boot=no,device-name=my-fgt-logdisk,mode=rw,name=disk-fgt-logdisk-$ZONE1_LABEL" \
  --tags=fgt \
  --metadata-from-file="user-data=metadata_active.txt,license=lic1.lic" \
  --async

gcloud compute instances create vm-fgt-$ZONE2_LABEL --zone=$ZONE2 \
  --machine-type=e2-standard-4 \
  --image=$FGT_IMG_URL \
  --can-ip-forward \
  --network-interface="network=vpc-external,subnet=sb-ext-$REGION_LABEL,no-address,private-network-ip=ip-fgt-ext-$ZONE2_LABEL" \
  --network-interface="network=vpc-internal-$REGION_LABEL,subnet=sb-int-$REGION_LABEL,no-address,private-network-ip=ip-fgt-int-$ZONE2_LABEL" \
  --network-interface="network=vpc-fgt-hasync,subnet=sb-fgt-hasync-$REGION_LABEL,no-address,private-network-ip=ip-fgt-hasync-$ZONE2_LABEL" \
  --network-interface="network=vpc-fgt-mgmt,subnet=sb-fgt-mgmt-$REGION_LABEL,address=eip-fgt-mgmt-$ZONE2_LABEL" \
  --disk="auto-delete=yes,boot=no,device-name=my-fgt-logdisk,mode=rw,name=disk-fgt-logdisk-$ZONE2_LABEL" \
  --tags=fgt \
  --metadata-from-file="user-data=metadata_passive.txt,license=lic2.lic"

## enable access
gcloud compute firewall-rules create fw-fgt-hasync-allowall \
  --direction=INGRESS \
  --network=vpc-fgt-hasync \
  --action=ALLOW \
  --rules=all \
  --source-tags=fgt \
  --target-tags=fgt

gcloud compute firewall-rules create fw-fgt-mgmt-allow-mgmt \
  --direction=INGRESS \
  --network=vpc-fgt-mgmt \
  --action=ALLOW \
  --rules="tcp:22,tcp:443" \
  --source-ranges=0.0.0.0/0 \
  --target-tags=fgt

gcloud compute firewall-rules create fw-ext-to-fgt-allowall \
  --direction=INGRESS \
  --network=vpc-external \
  --action=ALLOW \
  --rules=all \
  --source-ranges=0.0.0.0/0 \
  --target-tags=fgt

gcloud compute firewall-rules create fw-int-to-fgt-allowall \
  --direction=INGRESS \
  --network=vpc-internal-$REGION_LABEL \
  --action=ALLOW \
  --rules=all \
  --source-ranges=0.0.0.0/0 \
  --target-tags=fgt


gcloud compute routers create cr-fgt-nat-$REGION_LABEL --region=$REGION \
  --network=vpc-external
gcloud compute routers nats create nat-fgt-nat-$REGION_LABEL --region=$REGION \
  --router=cr-fgt-nat-$REGION_LABEL \
  --nat-custom-subnet-ip-ranges=sb-ext-$REGION_LABEL \
  --auto-allocate-nat-external-ips


## add instances to UMIGs
gcloud compute instance-groups unmanaged create umig-fgt-$ZONE1_LABEL --zone=$ZONE1
gcloud compute instance-groups unmanaged create umig-fgt-$ZONE2_LABEL --zone=$ZONE2

gcloud compute instance-groups unmanaged add-instances umig-fgt-$ZONE1_LABEL \
  --instances=vm-fgt-$ZONE1_LABEL \
  --zone=$ZONE1

gcloud compute instance-groups unmanaged add-instances umig-fgt-$ZONE2_LABEL \
  --instances=vm-fgt-$ZONE2_LABEL \
  --zone=$ZONE2

# ILB Internal
## health check
gcloud compute health-checks create http hc-fgtilb-tcp8008 --region=$REGION \
  --port=8008 \
  --timeout=2s \
  --healthy-threshold=1

## port2 ILB
gcloud compute backend-services create bes-fgtilb-internal-$REGION_LABEL --region=$REGION \
  --network=vpc-internal-$REGION_LABEL \
  --load-balancing-scheme=INTERNAL \
  --health-checks=hc-fgtilb-tcp8008 \
  --health-checks-region=$REGION

gcloud compute backend-services add-backend bes-fgtilb-internal-$REGION_LABEL --region=$REGION \
  --instance-group=umig-fgt-$ZONE1_LABEL \
  --instance-group-zone=$ZONE1
gcloud compute backend-services add-backend bes-fgtilb-internal-$REGION_LABEL --region=$REGION\
  --instance-group=umig-fgt-$ZONE2_LABEL \
  --instance-group-zone=$ZONE2

gcloud compute forwarding-rules create fr-fgtilb-int-$REGION_LABEL-tcp --region=$REGION \
  --address=ip-fgtilb-int-$REGION_LABEL \
  --ip-protocol=TCP \
  --ports=ALL \
  --load-balancing-scheme=INTERNAL \
  --backend-service=bes-fgtilb-internal-$REGION_LABEL \
  --subnet=sb-int-$REGION_LABEL

gcloud compute routes create rt-wrkld-$REGION_LABEL-to-untrust-via-fgt \
  --network=vpc-internal-$REGION_LABEL \
  --destination-range=192.168.0.0/16 \
  --next-hop-ilb=fr-fgtilb-int-$REGION_LABEL-tcp \
  --next-hop-ilb-region=$REGION

ssh admin@$EIP_MGMT "config system interface
edit port2
set secondary-IP enable
config secondaryip
edit 1
set ip $(gcloud compute addresses describe ip-fgtilb-int-$REGION_LABEL --format='get(address)' --region=$REGION) 255.255.255.255
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
gcloud compute backend-services create bes-fgtilb-external-$REGION_LABEL --region=$REGION \
  --network=vpc-external \
  --load-balancing-scheme=INTERNAL \
  --health-checks=hc-fgtilb-tcp8008 \
  --health-checks-region=$REGION

gcloud compute backend-services add-backend bes-fgtilb-external-$REGION_LABEL --region=$REGION \
  --instance-group=umig-fgt-$ZONE1_LABEL \
  --instance-group-zone=$ZONE1
gcloud compute backend-services add-backend bes-fgtilb-external-$REGION_LABEL --region=$REGION\
  --instance-group=umig-fgt-$ZONE2_LABEL \
  --instance-group-zone=$ZONE2

gcloud compute forwarding-rules create fr-fgtilb-ext-$REGION_LABEL-tcp --region=$REGION \
  --address=ip-fgtilb-ext-$REGION_LABEL \
  --ip-protocol=TCP \
  --ports=ALL \
  --load-balancing-scheme=INTERNAL \
  --backend-service=bes-fgtilb-external-$REGION_LABEL \
  --subnet=sb-ext-$REGION_LABEL

gcloud compute routes create rt-untrust-to-wrkld-$REGION_LABEL-via-fgt \
  --network=vpc-external \
  --destination-range=10.0.0.0/9 \
  --next-hop-ilb=fr-fgtilb-ext-$REGION_LABEL-tcp \
  --next-hop-ilb-region=$REGION

ssh admin@$EIP_MGMT "config system interface
edit port1
set secondary-IP enable
config secondaryip
edit 1
set ip $(gcloud compute addresses describe ip-fgtilb-ext-$REGION_LABEL --format='get(address)' --region=$REGION) 255.255.255.255
set allowaccess probe-response
next
end
next
end"

## port1 ELB
gcloud beta compute backend-services create bes-fgtelb-external-$REGION_LABEL --region=$REGION \
  --load-balancing-scheme=EXTERNAL \
  --protocol=UNSPECIFIED \
  --health-checks=hc-fgtilb-tcp8008 \
  --health-checks-region=$REGION

gcloud compute backend-services add-backend bes-fgtelb-external-$REGION_LABEL --region=$REGION \
  --instance-group=umig-fgt-$ZONE1_LABEL \
  --instance-group-zone=$ZONE1
gcloud compute backend-services add-backend bes-fgtelb-external-$REGION_LABEL --region=$REGION\
  --instance-group=umig-fgt-$ZONE2_LABEL \
  --instance-group-zone=$ZONE2

gcloud beta compute forwarding-rules create efr-fgtelb-serv1-$REGION_LABEL-l3 --region=$REGION \
  --address=eip-serv1-$REGION_LABEL \
  --ip-protocol=L3_DEFAULT \
  --ports=ALL \
  --load-balancing-scheme=EXTERNAL \
  --backend-service=bes-fgtelb-external-$REGION_LABEL

ssh admin@$EIP_MGMT "config system interface
edit port1
set secondary-IP enable
config secondaryip
edit 11
set ip $(gcloud compute addresses describe eip-serv1-$REGION_LABEL --format='get(address)' --region=$REGION) 255.255.255.255
set allowaccess probe-response
next
end
next
end"

# TODO: Peering
