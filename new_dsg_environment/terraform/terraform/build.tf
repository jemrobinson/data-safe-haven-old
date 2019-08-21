variable "resource_group_networks_name" {
  default = "RG_TERRAFORM_NETWORKS"
}

variable "resource_group_compute_name" {
  default = "RG_TERRAFORM_COMPUTE"
}

variable "resource_group_rds_name" {
  default = "RG_TERRAFORM_RDS"
}

module "networks" {
  source         = "./networks"
  location       = "${var.infrastructure_location}"
  azure_group_id = "${var.azure_group_id}"
  resource_group = "${var.resource_group_networks_name}"
  tenant_id      = "${var.tenant_id}"
}

# module "datasources" {
#   source               = "./datasources"
#   boot_diagnostics_uri = "${module.infrastructure.boot_diagnostics_uri}"
#   keyvault_id          = "${module.infrastructure.keyvault_id}"
#   location             = "${var.infrastructure_location}"
#   resource_group       = "${var.resource_group_datasources}"
#   resource_group_db    = "${var.resource_group_databases}"
#   acr_login_server     = "${module.infrastructure.acr_login_server}"
#   acr_admin_user       = "${module.infrastructure.acr_admin_user}"
#   acr_admin_password   = "${module.infrastructure.acr_admin_password}"
# }
