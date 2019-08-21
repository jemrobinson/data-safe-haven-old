terraform {
  backend "azurerm" {
    storage_account_name = "terraformstorageqvqh5ut3"
    container_name       = "terraformbackend"
    key                  = "terraform.tfstate"
    access_key           = "x+zRTO6Ug+xMIFEbabFEmi5/oJQo3Ls1j2lNa5kHML2tlGnU7IZD1GHeSTE8vAJ972y8aj8ztMc+U01gcIQGmQ=="
  }
}
variable "subscription_id" {
    default = "0c126bf5-366e-48d2-9b34-96d2d24b98f4"
}
variable "tenant_id" {
    default = "4395f4a7-e455-4f95-8a9f-1fbaef6384f9"
}
variable "infrastructure_location" {
    default = "uksouth"
}
variable "azure_group_id" {
    default = "347c68cb-261f-4a3e-ac3e-6af860b5fec9"
}
variable "diagnostics_storage_uri" {
    default = "347c68cb-261f-4a3e-ac3e-6af860b5fec9"
}
