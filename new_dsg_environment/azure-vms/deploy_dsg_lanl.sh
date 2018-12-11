#!/usr/bin/env bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

SUBSCRIPTION="DSG - Imperial/LANL"
COMPUTE_RG="RG_DSG_COMPUTE"
IMAGEBASE="ComputeVM-Ubuntu1804Base"
VERSION="0.0.2018120701"
IMAGE="/subscriptions/1e79c270-3126-43de-b035-22c3118dd488/resourceGroups/RG_SH_IMAGEGALLERY/providers/Microsoft.Compute/galleries/SIG_SH_COMPUTE/images/${IMAGEBASE}/versions/${VERSION}"

# Network resources
NETWORK_RG="RG_DSG_NETWORK"
VM_NAME="DSG$(date '+%Y%m%d%H%M')"
VM_SIZE="Standard_D2s_v3"
LOCATION="westeurope"
VNET="DSG_VNET"
SUBNET="Subnet-Data"
NSG="DSG_NSG"
RDP_PORT="3389"

# Credentials
MANAGEMENT_VAULT_NAME="dsg-imperial-lanl"
USERNAME="dsguser"
ADMIN_PASSWORD_SECRET_NAME="vm-admin-password"
# Retrieve admin password from keyvault
ADMIN_PASSWORD=$(az keyvault secret show --vault-name $MANAGEMENT_VAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

CLOUDINITYAML="cloud-init-new-lanl-conpute-vm.yaml"

# Ensure we are using the right subscritpion
az account set --subscription "$SUBSCRIPTION"

# Fetch Subnet ID
DSG_SUBNET_ID=$(az network vnet subnet list --resource-group $NETWORK_RG --vnet-name $VNET --query "[?name == '$SUBNET'].id | [0]" | xargs)
if [ "$DSG_SUBNET_ID" = "" ]; then
    echo -e "${RED}Could not find subnet ${BLUE}${SUBNET}${END} ${RED}for vnet ${BLUE}${VNET}${END}"
    exit 1
else
    echo -e "${BOLD}Found subnet ${BLUE}${SUBNET}${END} ${BOLD}for vnet ${BLUE}${VNET}${END}"
fi
# Fetch NSG ID
DSG_NSG_ID=$(az network nsg show --resource-group $NETWORK_RG --name $NSG --query 'id' | xargs)
if [ "$DSG_NSG_ID" = "" ]; then
    echo -e "${RED}Could not find NSG ${BLUE}${NSG}${END} ${RED}in RG ${BLUE}${NETWORK_RG}${END}"
    exit 1
else
    echo -e "${BOLD}Found NSG ${BLUE}${NSG}${END} ${BOLD}in RG ${BLUE}${NETWORK_RG}${END}"
fi

# Deploy VM
echo -e "${BOLD}Deploying a ${BLUE}${VM_SIZE}${END}${BOLD}VM as ${BLUE}${VM_NAME}${END} ${BOLD}to subscription ${BLUE}${SUBSCRIPTION}${END} ${BOLD}in region ${BLUE}${LOCATION}${END} ${BOLD}using gallery image ${BLUE}${IMAGEBASE}${END} ${BOLD}version ${BLUE}${VERSION}${END}"
az vm create \
    --resource-group "$COMPUTE_RG" \
    --image "$IMAGE" \
    --name "$VM_NAME" \
    --size "$VM_SIZE" \
    --location "$LOCATION" \
    --subnet "${SUBNET_ID}" \
    --nsg "${NSG_ID}"  \
    --admin-username '$USERNAME" \
    --admin-password "$ADMIN_PASSWORD" \
    --custom-data "$CLOUDINITYAML"

# Display public IP
PUBLICIP=$(az vm list-ip-addresses --resource-group "$COMPUTE_RG" --name "$VM_NAME" --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | xargs echo)
echo -e "${BOLD}This new VM can be accessed with remote desktop at ${BLUE}${PUBLICIP}:${RDP_PORT}${END}"
