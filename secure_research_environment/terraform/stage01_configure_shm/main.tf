# Load configuration module
# -------------------------
module "configuration" {
  source = "../configuration"
}
# Key Vault Configuration
# -----------------------
data "azurerm_client_config" "current" {}

# Create the secrets resource group
# ---------------------------------
resource "azurerm_resource_group" "this" {
  name     = "${module.configuration.dsg_keyVault_rg}"
  location = "${module.configuration.dsg_location}"
}

# Create the keyvault where passwords are stored
# ----------------------------------------------
resource "azurerm_key_vault" "this" {
  name                = "${module.configuration.dsg_keyVault_name}"
  location            = "${module.configuration.dsg_location}"
  resource_group_name = "${azurerm_resource_group.this.name}"
  sku_name            = "standard"
  tenant_id           = "${module.configuration.tenant_id}"

  access_policy {
    tenant_id = "${module.configuration.tenant_id}"
    object_id = "${data.azurerm_client_config.current.object_id}"

    secret_permissions = [
      "get", "list", "set", "delete"
    ]
  }
}

# Passwords from random strings
# -----------------------------
# :: HackMD password
resource "random_string" "hackmdPassword" {
  keepers = {
    resource_group = "${azurerm_resource_group.this.name}"
  }
  length  = 20
  special = false
}
resource "azurerm_key_vault_secret" "hackmdPassword" {
  name         = "${module.configuration.dsg_users_ldap_hackmd_passwordSecretName}"
  value        = "${random_string.hackmdPassword.result}"
  key_vault_id = "${azurerm_key_vault.this.id}"
}
# :: GitLab password
resource "random_string" "gitlabPassword" {
  keepers = {
    resource_group = "${azurerm_resource_group.this.name}"
  }
  length  = 20
  special = false
}
resource "azurerm_key_vault_secret" "gitlabPassword" {
  name         = "${module.configuration.dsg_users_ldap_gitlab_passwordSecretName}"
  value        = "${random_string.gitlabPassword.result}"
  key_vault_id = "${azurerm_key_vault.this.id}"
}
# :: DSVM password
resource "random_string" "dsvmPassword" {
  keepers = {
    resource_group = "${azurerm_resource_group.this.name}"
  }
  length  = 20
  special = false
}
resource "azurerm_key_vault_secret" "dsvmPassword" {
  name         = "${module.configuration.dsg_users_ldap_dsvm_passwordSecretName}"
  value        = "${random_string.gitlabPassword.result}"
  key_vault_id = "${azurerm_key_vault.this.id}"
}
# :: Test researcher password
resource "random_string" "testResearcherPassword" {
  keepers = {
    resource_group = "${azurerm_resource_group.this.name}"
  }
  length  = 20
  special = false
}
resource "azurerm_key_vault_secret" "testResearcherPassword" {
  name         = "${module.configuration.dsg_users_researchers_test_passwordSecretName}"
  value        = "${random_string.testResearcherPassword.result}"
  key_vault_id = "${azurerm_key_vault.this.id}"
}

# Create new DSG user service accounts
# ------------------------------------
# Trigger => run every time
resource "null_resource" "Create_New_DSG_User_Service_Accounts_Remote" {
    triggers = {
        trigger = "${uuid()}"
    }
    provisioner "local-exec" {
      command = join(" ", [".'${path.module}/../../../new_dsg_environment/dsg_deploy_scripts/01_configure_shm_dc/helper_scripts/Prepare_SHM/remote_scripts/Create_New_DSG_User_Service_Accounts_Remote.ps1'",
                     "-dsgFqdn '${module.configuration.dsg_domain_fqdn}'",
                     "-researchUserSgName '${module.configuration.dsg_domain_securityGroups_researchUsers_name}'",
                     "-researchUserSgDescription '${module.configuration.dsg_domain_securityGroups_researchUsers_description}'",
                     "-ldapUserSgName '${module.configuration.shm_domain_securityGroups_dsvmLdapUsers_name}'",
                     "-securityOuPath '${module.configuration.shm_domain_securityOuPath}'",
                     "-serviceOuPath '${module.configuration.shm_domain_serviceOuPath}'",
                     "-researchUserOuPath '${module.configuration.shm_domain_userOuPath}'",
                     "-hackmdSamAccountName '${module.configuration.dsg_users_ldap_hackmd_samAccountName}'",
                     "-hackmdName '${module.configuration.dsg_users_ldap_hackmd_name}'",
                     "-hackmdPassword ${azurerm_key_vault_secret.hackmdPassword.value}'",
                     "-gitlabSamAccountName '${module.configuration.dsg_users_ldap_gitlab_samAccountName}'",
                     "-gitlabName '${module.configuration.dsg_users_ldap_gitlab_name}'",
                     "-gitlabPassword ${azurerm_key_vault_secret.gitlabPassword.value}'",
                     "-dsvmSamAccountName '${module.configuration.dsg_users_ldap_dsvm_samAccountName}'",
                     "-dsvmName '${module.configuration.dsg_users_ldap_dsvm_name}'",
                     "-dsvmPassword ${azurerm_key_vault_secret.dsvmPassword.value}'",
                     "-testResearcherSamAccountName '${module.configuration.dsg_users_researchers_test_samAccountName}'",
                     "-testResearcherName '${module.configuration.dsg_users_researchers_test_name}'",
                     "-testResearcherPassword ${azurerm_key_vault_secret.testResearcherPassword.value}'"])
      interpreter = ["pwsh", "-Command"]
    }
}