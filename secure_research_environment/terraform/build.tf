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
# module "networks" {
#   source         = "./networks"
#   location       = "${var.infrastructure_location}"
#   azure_group_id = "${var.azure_group_id}"
#   resource_group = "${var.resource_group_networks_name}"
#   tenant_id      = "${var.tenant_id}"
# }
