# Load configuration module
# -------------------------
module "configuration" {
  source = "../configuration"
}

# Explicitly take providers as an argument, or they cannot be referenced
# ----------------------------------------------------------------------
provider "azurerm" {}
provider "azurerm" { alias = "shm_management" }

# Create the network resource group
# ---------------------------------
resource "azurerm_resource_group" "this" {
  name     = "${module.configuration.dsg_network_vnet_rg}"
  location = "${module.configuration.dsg_location}"
}

# Create the virtual network and subnets
# --------------------------------------
resource "azurerm_virtual_network" "this" {
  name                = "${module.configuration.dsg_network_vnet_name}"
  address_space       = ["${module.configuration.dsg_network_vnet_cidr}"]
  location            = "${module.configuration.dsg_location}"
  resource_group_name = "${azurerm_resource_group.this.name}"
  dns_servers         = ["${module.configuration.dsg_dc_ip}"]
}
# Identity subnet
resource "azurerm_subnet" "identity" {
  address_prefix       = "${module.configuration.dsg_network_subnets_identity_cidr}"
  name                 = "IdentitySubnet"
  resource_group_name  = "${azurerm_resource_group.this.name}"
  virtual_network_name = "${azurerm_virtual_network.this.name}"
}
# RDS subnet
resource "azurerm_subnet" "rds" {
  address_prefix       = "${module.configuration.dsg_network_subnets_rds_cidr}"
  name                 = "RDSSubnet"
  resource_group_name  = "${azurerm_resource_group.this.name}"
  virtual_network_name = "${azurerm_virtual_network.this.name}"
}
# Data subnet
resource "azurerm_subnet" "data" {
  address_prefix       = "${module.configuration.dsg_network_subnets_data_cidr}"
  name                 = "DataSubnet"
  resource_group_name  = "${azurerm_resource_group.this.name}"
  virtual_network_name = "${azurerm_virtual_network.this.name}"
}
# Gateway subnet
resource "azurerm_subnet" "gateway" {
  address_prefix       = "${module.configuration.dsg_network_subnets_gateway_cidr}"
  name                 = "GatewaySubnet"
  resource_group_name  = "${azurerm_resource_group.this.name}"
  virtual_network_name = "${azurerm_virtual_network.this.name}"
}

# Read secrets from the management key vault
# ------------------------------------------
# Get handle to key vault in SHM management
data "azurerm_key_vault" "shm_management" {
  provider            = azurerm.shm_management
  name                = "${module.configuration.shm_keyVault_name}"
  resource_group_name = "${module.configuration.shm_keyVault_rg}"
}
data "azurerm_key_vault_secret" "p2sRootCert" {
  provider     = azurerm.shm_management
  name         = "${module.configuration.shm_keyVault_secretNames_p2sRootCert}"
  key_vault_id = "${data.azurerm_key_vault.shm_management.id}"
}

# Create the VPN gateway
# ----------------------
# Create a public IP for the gateway
resource "azurerm_public_ip" "gateway" {
  name                = "VNET_GW_PIP"
  location            = "${module.configuration.dsg_location}"
  resource_group_name = "${azurerm_resource_group.this.name}"
  allocation_method   = "Dynamic"
}
# Create the gateway
resource "azurerm_virtual_network_gateway" "gateway" {
  active_active       = false
  enable_bgp          = false
  location            = "${module.configuration.dsg_location}"
  name                = "VNET_GW"
  resource_group_name = "${azurerm_resource_group.this.name}"
  sku                 = "Basic"
  type                = "Vpn"
  vpn_type            = "RouteBased"

  ip_configuration {
    name                          = "vnetGatewayIPConfig"
    public_ip_address_id          = "${azurerm_public_ip.gateway.id}"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = "${azurerm_subnet.gateway.id}"
  }

  vpn_client_configuration {
    address_space = ["172.16.201.0/24"]

    root_certificate {
      name             = "DSG_P2S_RootCert.cer"
      public_cert_data = "${data.azurerm_key_vault_secret.p2sRootCert.value}"
    }
  }
}

# Peer the virtual network
# ------------------------
# Get handle to virtual network in SHM management
data "azurerm_virtual_network" "shm_management" {
  provider            = azurerm.shm_management
  name                = "${module.configuration.shm_network_vnet_name}"
  resource_group_name = "${module.configuration.shm_network_vnet_rg}"
}
# Peer this network to the remote one
resource "azurerm_virtual_network_peering" "this_to_remote" {
  name                         = "PEER_${data.azurerm_virtual_network.shm_management.name}"
  resource_group_name          = "${azurerm_resource_group.this.name}"
  virtual_network_name         = "${azurerm_virtual_network.this.name}"
  remote_virtual_network_id    = "${data.azurerm_virtual_network.shm_management.id}"
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
# Peer the remote network to this one
resource "azurerm_virtual_network_peering" "remote_to_this" {
  provider                     = azurerm.shm_management
  name                         = "PEER_${azurerm_virtual_network.this.name}"
  resource_group_name          = "${module.configuration.shm_network_vnet_rg}"
  virtual_network_name         = "${data.azurerm_virtual_network.shm_management.name}"
  remote_virtual_network_id    = "${azurerm_virtual_network.this.id}"
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
