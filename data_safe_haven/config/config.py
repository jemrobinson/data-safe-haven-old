# Standard library imports
import pathlib
import re

# Third party imports
from azure.storage.blob import BlobServiceClient
from azure.mgmt.storage import StorageManagementClient
from azure.core.exceptions import ResourceNotFoundError
import dotmap
import yaml

# Local imports
from data_safe_haven import __version__
from data_safe_haven.exceptions import (
    DataSafeHavenAzureException,
    DataSafeHavenInputException,
)
from data_safe_haven.mixins import AzureMixin, LoggingMixin


class Config(LoggingMixin, AzureMixin):
    alphanumeric = re.compile(r"[^0-9a-zA-Z]+")
    storage_container_name = "config"

    def __init__(self, path, *args, **kwargs):
        try:
            with open(pathlib.Path(path), "r") as f_config:
                base_yaml = yaml.safe_load(f_config)
        except Exception as exc:
            raise DataSafeHavenInputException(
                f"Could not load config YAML file '{path}'"
            ) from exc

        # Set common properties
        self.environment_name = self.alphanumeric.sub(
            "", base_yaml["environment"]["name"]
        ).lower()
        self.resource_group_name = f"rg-{self.environment_name}-backend"
        self.storage_account_name = f"st{self.environment_name}backend"

        # Load the Azure mixin
        super().__init__(
            *args, subscription_name=base_yaml["azure"]["subscription_name"], **kwargs
        )

        # Try to load the full config from blob storage
        try:
            self._map = self.download()
        # ... otherwise create a new DotMap
        except (DataSafeHavenAzureException, ResourceNotFoundError):
            self._map = dotmap.DotMap()

        # Update the map with local config variables
        self.add_data(base_yaml)
        self.tags.deployed_by = "Python"
        self.tags.project = "Data Safe Haven"
        self.tags.version = __version__
        self.backend.resource_group_name = self.resource_group_name
        self.backend.storage_account_name = self.storage_account_name
        self.settings.allow_copy = (
            False
            if isinstance(self.settings.allow_copy, dotmap.DotMap)
            else self.settings.allow_copy
        )
        self.settings.allow_paste = (
            False
            if isinstance(self.settings.allow_paste, dotmap.DotMap)
            else self.settings.allow_paste
        )
        self.settings.timezone = (
            "Europe/London"
            if isinstance(self.settings.timezone, dotmap.DotMap)
            else self.settings.timezone
        )

    def __repr__(self):
        return f"{self.__class__} containing: {self._map}"

    def __str__(self):
        return yaml.dump(self._map.toDict(), indent=2)

    def __getattr__(self, name):
        return self._map[name]

    @property
    def name(self):
        return f"config-{self.environment_name}.yaml"

    def add_data(self, dicts):
        self._map = self.merge_dicts(self._map, dicts)

    def backend_exists(self):
        try:
            _ = self.storage_account_key()
        except DataSafeHavenAzureException:
            return False
        return True

    def download(self):
        """Load the config file from Azure storage"""
        # Connect to blob storage
        blob_connection_string = f"DefaultEndpointsProtocol=https;AccountName={self.storage_account_name};AccountKey={self.storage_account_key()};EndpointSuffix=core.windows.net"
        blob_service_client = BlobServiceClient.from_connection_string(
            blob_connection_string
        )
        # Download the created file
        blob_client = blob_service_client.get_blob_client(
            container=self.storage_container_name, blob=self.name
        )
        return dotmap.DotMap(yaml.safe_load(blob_client.download_blob().readall()))

    def merge_dicts(self, d_old, d_new):
        for key, value in d_new.items():
            if isinstance(value, dict):
                if key in d_old:
                    d_old[key] = self.merge_dicts(d_old[key], value)
                else:
                    d_old[key] = dotmap.DotMap(value)
            else:
                d_old[key] = value
        return d_old

    def storage_account_key(self):
        """Load the key for the backend storage account"""
        try:
            storage_client = StorageManagementClient(
                self.credential, self.subscription_id
            )
            storage_keys = storage_client.storage_accounts.list_keys(
                self.resource_group_name,
                self.storage_account_name,
            )
            return storage_keys.keys[0].value
        except Exception as exc:
            raise DataSafeHavenAzureException(
                "Storage key could not be loaded."
            ) from exc

    def upload(self):
        """Dump the config file to Azure storage"""
        self.info(
            f"Uploading config <fg=green>{self.name}</> to blob storage.",
            no_newline=True,
        )
        # Connect to blob storage
        blob_connection_string = f"DefaultEndpointsProtocol=https;AccountName={self.storage_account_name};AccountKey={self.storage_account_key()};EndpointSuffix=core.windows.net"
        blob_service_client = BlobServiceClient.from_connection_string(
            blob_connection_string
        )
        # Upload the created file
        blob_client = blob_service_client.get_blob_client(
            container=self.storage_container_name,
            blob=f"config-{self.environment_name}.yaml",
        )
        blob_client.upload_blob(self.__str__(), overwrite=True)
        self.info(
            f"Uploaded config <fg=green>{self.name}</> to blob storage.", overwrite=True
        )
