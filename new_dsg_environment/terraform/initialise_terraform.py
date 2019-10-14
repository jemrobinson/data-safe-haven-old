#! /usr/bin/env python
import argparse
import json
import logging
import os
import random
import string
import termcolor
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.resource.subscriptions import SubscriptionClient
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.storage.models import StorageAccountCreateParameters, Sku, SkuName, Kind
from azure.storage.blob import BlockBlobService


def emphasised(text):
    return termcolor.colored(text, 'green')


def get_subscription(credentials, subscription_name):
    # Switch to appropriate subscription
    subscription_client = SubscriptionClient(credentials)
    subscription = [s for s in subscription_client.subscriptions.list() if s.display_name == subscription_name][0]
    logging.info("Working in subscription: %s", emphasised(subscription.display_name))
    return subscription


def ensure_resource_group(credentials, subscription_id, resource_group, location):
    # Create the backend resource group
    logging.info("Ensuring existence of resource group: %s", emphasised(resource_group))
    resource_mgmt_client = ResourceManagementClient(credentials, subscription_id=subscription_id)
    resource_mgmt_client.resource_groups.create_or_update(resource_group, {"location": location})


def get_storage_account(credentials, subscription_id, resource_group, location):
    # Check whether there is already a storage account and generate one if not
    storage_mgmt_client = StorageManagementClient(credentials, subscription_id=subscription_id)
    storage_account_name = None
    for storage_account in storage_mgmt_client.storage_accounts.list_by_resource_group(resource_group):
        if "terraformstorage" in storage_account.name:
            storage_account_name = storage_account.name
            break
    if storage_account_name:
        logging.info("Found existing storage account named: %s", emphasised(storage_account_name))
    else:
        storage_account_name = generate_new_storage_account(storage_mgmt_client, resource_group, location)
    return storage_account_name


def get_storage_account_key(credentials, subscription_id, resource_group, storage_account_name, storage_container_name):
    # Get the account key for this storage account
    storage_mgmt_client = StorageManagementClient(credentials, subscription_id=subscription_id)
    storage_key_list = storage_mgmt_client.storage_accounts.list_keys(resource_group, storage_account_name)
    storage_account_key = [k.value for k in storage_key_list.keys if k.key_name == "key1"][0]

    # Ensure that the container exists
    logging.info("Ensuring existence of storage container: {}".format(emphasised(storage_container_name)))
    block_blob_service = BlockBlobService(account_name=storage_account_name, account_key=storage_account_key)
    if not block_blob_service.exists(storage_container_name):
        block_blob_service.create_container(storage_container_name)
    return storage_account_key


def write_terraform_config(**kwargs):
    # Write Terraform configuration
    config_file_lines = [
        'terraform {',
        '  backend "azurerm" {',
        '    storage_account_name = "{}"'.format(kwargs["storage_account_name"]),
        '    container_name       = "{}"'.format(kwargs["storage_container_name"]),
        '    key                  = "terraform.tfstate"',
        '    access_key           = "{}"'.format(kwargs["storage_account_key"]),
        '  }',
        '}',
        'variable "subscription_id" {',
        '    default = "{}"'.format(kwargs["subscription_id"]),
        '}',
        'variable "tenant_id" {',
        '    default = "{}"'.format(kwargs["tenant_id"]),
        '}',
        'variable "infrastructure_location" {',
        '    default = "{}"'.format(kwargs["location"]),
        '}',
        'variable "azure_group_id" {',
        '    default = "{}"'.format(kwargs["azure_group_id"]),
        '}',
        ]

    # Write Terraform backend config
    filepath = os.path.join("terraform", "config.tf")
    logging.info("Writing Terraform backend config to: {}".format(emphasised(filepath)))
    with open(filepath, "w") as f_config:
        for line in config_file_lines:
            f_config.write(line + "\n")


def generate_new_storage_account(storage_mgmt_client, resource_group, location):
    """Create a new storage account."""
    def get_valid_storage_account_name(storage_mgmt_client):
        """Keep generating storage account names until a valid one is found."""
        while True:
            storage_account_name = "terraformstorage"
            storage_account_name += "".join([random.choice(string.ascii_lowercase + string.digits) for n in range(24 - len(storage_account_name))])
            if storage_mgmt_client.storage_accounts.check_name_availability(storage_account_name).name_available:
                return storage_account_name
    storage_account_name = get_valid_storage_account_name(storage_mgmt_client)
    logging.info("Creating new storage account: {}".format(emphasised(storage_account_name)))
    storage_async_operation = storage_mgmt_client.storage_accounts.create(
        resource_group,
        storage_account_name,
        StorageAccountCreateParameters(
            sku=Sku(name=SkuName.standard_lrs),
            kind=Kind.storage,
            location=location
        )
    )
    # Wait until storage_async_operation has finished before returning
    storage_async_operation.result()
    return storage_account_name


def authenticate_device_code(tenant):
    """
    Authenticate the end-user using device auth.
    """
    import adal
    from msrestazure.azure_active_directory import AADTokenCredentials
    authority_host_uri = 'https://login.microsoftonline.com'
    authority_uri = authority_host_uri + '/' + tenant
    resource_uri = 'https://management.core.windows.net/'
    client_id = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'  # Microsoft ID

    context = adal.AuthenticationContext(authority_uri, api_version=None)
    code_prompt = context.acquire_user_code(resource_uri, client_id)
    print(code_prompt['message'])
    mgmt_token = context.acquire_token_with_device_code(resource_uri, code_prompt, client_id)
    credentials = AADTokenCredentials(mgmt_token, client_id)
    return credentials


def main():
    # Read command line arguments
    parser = argparse.ArgumentParser(description='Initialise the Azure infrastructure needed by Terraform')
    parser.add_argument("-g", "--resource-group", type=str, default="RG_TERRAFORM_BACKEND", help="Resource group where the Terraform backend will be stored")
    parser.add_argument("-c", "--config", type=str, default="dsg_9_full_config.json", help="Name of the configuration file to use")
    parser.add_argument("-a", "--azure-group-id", type=str, default="347c68cb-261f-4a3e-ac3e-6af860b5fec9", help="ID of an Azure group which contains all project developers. Default is Turing's 'Safe Haven Test Admins' group.")
    args = parser.parse_args()

    # Load configuration from file
    filepath = os.path.join("..", "dsg_configs", "full", args.config)
    with open(filepath, "r") as f_config:
        config = json.load(f_config)

    # Get credentials using our tenant ID
    credentials = authenticate_device_code(tenant="4395f4a7-e455-4f95-8a9f-1fbaef6384f9")
    subscription_name = config["dsg"]["subscriptionName"]
    location = config["dsg"]["location"]
    storage_container_name = "terraformbackend"

    # Switch to the correct subscription
    subscription = get_subscription(credentials, subscription_name)

    # Ensure that the resource group exists
    ensure_resource_group(credentials, subscription.subscription_id, args.resource_group, location)

    # Get the name of the storage account, creating one if necessary
    storage_account_name = get_storage_account(credentials, subscription.subscription_id,
                                               args.resource_group, location)

    # Get the name of the storage container,  creating one if necessary
    storage_account_key = get_storage_account_key(credentials, subscription.subscription_id, args.resource_group,
                                                  storage_account_name, storage_container_name)

    # Write configuration to Terraform
    kwargs = {
        "azure_group_id": args.azure_group_id,
        "location": location,
        "storage_account_key": storage_account_key,
        "storage_account_name": storage_account_name,
        "storage_container_name": storage_container_name,
        "subscription_id": subscription.subscription_id,
        "tenant_id": subscription.tenant_id,
    }
    write_terraform_config(**kwargs)


if __name__ == "__main__":
    # Set up logging
    logging.basicConfig(format=r"%(asctime)s %(levelname)8s: %(message)s", datefmt=r"%Y-%m-%d %H:%M:%S", level=logging.INFO)
    logging.getLogger("adal-python").setLevel(logging.WARNING)
    logging.getLogger("azure").setLevel(logging.WARNING)

    # Run main
    main()
