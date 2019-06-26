#! /bin/bash

# Load common constants and options
source ${BASH_SOURCE%/*}/configs/postgresql.sh
source ${BASH_SOURCE%/*}/configs/text.sh

# Document usage for this script
# ------------------------------
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription [-r resource_group]"
    echo "  -h                                    display help"
    echo "  -s subscription [required]            specify subscription where the mirror servers should be deployed. (Test using 'DSG Template Testing')"
    echo "  -m management_subscription [required] specify management subscription that contains secrets. (Test using 'Safe Haven Management Testing')"
    echo "  -k management_vault_name              specify name of KeyVault containing management secrets (defaults to '${KEYVAULT_NAME}')"
    echo "  -r resource_group                     specify resource group - will be created if it does not already exist (defaults to '${RESOURCEGROUP}')"
    exit 1
}


# Read command line arguments, overriding defaults where necessary
# ----------------------------------------------------------------
while getopts "hr:s:m:k:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        k)
            KEYVAULT_NAME=$OPTARG
            ;;
        m)
            SUBSCRIPTION_MANAGEMENT=$OPTARG
            ;;
        r)
            RESOURCEGROUP=$OPTARG
            ;;
        s)
            SUBSCRIPTION_TARGET=$OPTARG
            ;;
        \?)
            print_usage_and_exit
            ;;
    esac
done


# Check that a subscription has been provided and switch to it
# ------------------------------------------------------------
if [ "$SUBSCRIPTION_TARGET" = "" ]; then
    echo -e "${RED}Subscription is a required argument!${END}"
    print_usage_and_exit
fi


# Check that a management KeyVault name has been provided
# -------------------------------------------------------
if [ "$KEYVAULT_NAME" = "" ]; then
    echo -e "${RED}Management KeyVault name is a required argument!${END}"
    print_usage_and_exit
fi


# Ensure that postgres server exists
# -------------------------------------
az account set --subscription "$SUBSCRIPTION_TARGET"
SERVER_NAME="dsg-postgres-$(date '+%Y%m%d%H%M')"
EXISTING_SERVERS=$(az postgres server list --query "[?resourceGroup=='$RESOURCEGROUP'].name" -o tsv | grep dsg-postgres)
if [ "$EXISTING_SERVERS" != "" ]; then
    SERVER_NAME=$EXISTING_SERVERS
    echo -e "${BOLD}Found Postgres server ${BLUE}$SERVER_NAME${END} ${BOLD}in resource group ${BLUE}$RESOURCEGROUP${END}"
else
    echo -e "${BOLD}Creating Postgres server ${BLUE}$SERVER_NAME${END} ${BOLD}in resource group ${BLUE}$RESOURCEGROUP${END}"

    # Retrieve admin password from keyvault
    az account set --subscription "$SUBSCRIPTION_MANAGEMENT"
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_NAME --query "value" | xargs)
    az account set --subscription "$SUBSCRIPTION_TARGET"

    # Create postgres server
    az postgres server create --resource-group $RESOURCEGROUP \
                              --name $SERVER_NAME \
                              --location $LOCATION \
                              --admin-user $ADMIN_USERNAME \
                              --admin-password $ADMIN_PASSWORD \
                              --sku-name GP_Gen5_2 \
                              --version 9.6
fi

# Check that VNET exists
# ----------------------
VNET_RG=""
for RG in $(az group list --query "[].name" -o tsv); do
    if [ "$(az network vnet show --resource-group $RG --name $VNET_NAME --query "name" -o tsv 2> /dev/null)" == "$VNET_NAME" ]; then
        VNET_RG=$RG
    fi
done
if [ "$VNET_RG" = "" ]; then
    echo -e "${RED}Could not find VNet ${BLUE}$VNET_RG${RED} in any resource group${END}"
    print_usage_and_exit
fi

# Ensure that subnet exists
# -------------------------
SUBNET_ID=$(az network vnet subnet show --resource-group $VNET_RG --vnet-name $VNET_NAME --name $SUBNET_DATA --query 'id' -o tsv 2> /dev/null)
if [ "$SUBNET_ID" == "" ]; then
    echo -e "${BOLD}Creating subnet ${BLUE}$SUBNET_EXTERNAL${END} ${BOLD}as part of VNet ${BLUE}$VNET_NAME${END}"
    az network vnet subnet create \
        --address-prefix $SUBNET_IP_RANGE \
        --name $SUBNET_DATA \
        --resource-group $VNET_RG \
        --service-endpoints Microsoft.SQL \
        --vnet-name $VNET_NAME
else
    echo -e "${BOLD}Updating subnet ${BLUE}$SUBNET_DATA${END} ${BOLD}as part of VNet ${BLUE}$VNET_NAME${END}"
    az network vnet subnet update \
        --resource-group $VNET_RG \
        --name $SUBNET_DATA \
        --service-endpoints Microsoft.SQL \
        --vnet-name $VNET_NAME
fi

# Create VNet rule
# ----------------
echo -e "${BOLD}Creating VNet rule for ${BLUE}$SERVER_NAME${END}"
az postgres server vnet-rule create \
    --name VNET_BINDING \
    --resource-group $RESOURCEGROUP \
    --server-name $SERVER_NAME \
    --subnet $SUBNET_ID

# NB. DC lives in ukwest at:
# /subscriptions/1e79c270-3126-43de-b035-22c3118dd488/resourceGroups/RG_DSG_VNET/providers/Microsoft.Network/virtualNetworks/DSG_DSGROUPDEV_VNET1/subnets/Subnet_Identity
