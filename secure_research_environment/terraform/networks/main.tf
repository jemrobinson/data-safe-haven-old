# Setup required providers
provider "azurerm" {
  version = "=1.24"
}

provider "random" {
  version = "=2.1"
}

# Setup variables
variable "azure_group_id" {}

variable "location" {}
variable "resource_group" {}
variable "tenant_id" {}
