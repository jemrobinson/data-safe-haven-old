module "stage01_configure_shm" {
  source = "./stage01_configure_shm"
}

module "stage02_create_vnet" {
  source = "./stage02_create_vnet"
  providers = {
    azurerm = "azurerm",
    azurerm.shm_management = "azurerm.shm_management"
  }
}

module "stage03_create_dc" {
  source = "./stage03_create_dc"
  dsg_keyVault_dcAdminPassword = "${module.stage01_configure_shm.dsg_keyVault_dcAdminPassword}"
  dsg_network_subnets_identity_id = "${module.stage02_create_vnet.dsg_network_subnets_identity_id}"
}