# Standard library imports
import binascii
import os
from typing import Optional

# Third party imports
from pulumi import Input, ResourceOptions
from pulumi.dynamic import (
    Resource,
    ResourceProvider,
    CreateResult,
    DiffResult,
    UpdateResult,
)
import simple_acme_dns

# Local imports
from data_safe_haven.external import AzureApi
from data_safe_haven.exceptions import DataSafeHavenSSLException


class SSLCertificateProps:
    """Props for the SSLCertificate class"""

    def __init__(
        self,
        certificate_secret_name: Input[str],
        domain_name: Input[str],
        key_vault_name: Input[str],
        networking_resource_group_name: Input[str],
        subscription_name: Input[str],
    ):
        self.certificate_secret_name = certificate_secret_name
        self.domain_name = domain_name
        self.key_vault_name = key_vault_name
        self.networking_resource_group_name = networking_resource_group_name
        self.subscription_name = subscription_name


class _SSLCertificateProps:
    """Unwrapped version of SSLCertificateProps"""

    def __init__(
        self,
        domain_name: str,
        key_vault_name: str,
        networking_resource_group_name: str,
        subscription_name: str,
    ):
        self.domain_name = domain_name.lower()
        self.key_vault_name = key_vault_name
        self.networking_resource_group_name = networking_resource_group_name
        self.subscription_name = subscription_name


class SSLCertificateProvider(ResourceProvider):
    def create(self, props: _SSLCertificateProps) -> CreateResult:
        """Create new SSL certificate."""
        try:
            # Note that we must set the key to RSA-2048 before generating the CSR
            # The default is ecdsa-with-SHA25, which Azure Key Vault cannot read
            client = simple_acme_dns.ACMEClient(
                domains=[props["domain_name"]],
                email="jrobinson@turing.ac.uk",
                directory="https://acme-staging-v02.api.letsencrypt.org/directory",
                nameservers=["8.8.8.8", "1.1.1.1"],
                new_account=True,
            )
            # Generate private key and CSR
            private_key = client.generate_private_key(key_type="rsa2048")
            csr = client.generate_csr()
            # Request DNS verification tokens and add them to the DNS record
            azure_api = AzureApi(props["subscription_name"])
            for token in client.request_verification_tokens():
                azure_api.ensure_dns_txt_record(
                    record_name=token[0].replace(f".{props['domain_name']}", ""),
                    record_value=token[1],
                    resource_group_name=props["networking_resource_group_name"],
                    zone_name=props["domain_name"],
                )
            # Wait for DNS propagation to complete
            result = client.check_dns_propagation(
                timeout=1,
                interval=5,
                authoritative=False,
                round_robin=True,
                verbose=False,
            )
            # Request a signed certificate
            certificate = client.request_certificate()
            # Key Vault requires us to prepend the private key and remove double line-breaks
            full_certificate = (private_key + b"\n" + certificate).replace(
                b"\n\n", b"\n"
            )
            # Add certificate to KeyVault
            azure_api.import_keyvault_certificate(
                certificate_name=props["certificate_secret_name"],
                certificate_contents=full_certificate,
                key_vault_name=props["key_vault_name"],
            )
        except Exception as exc:
            raise DataSafeHavenSSLException(
                f"Failed to create SSL certificate <fg=green>{props['certificate_secret_name']}</> for <fg=green>{props['domain_name']}</>."
            ) from exc
        return CreateResult(
            f"SSLCertificate-{binascii.b2a_hex(os.urandom(16)).decode('utf-8')}",
            outs=dict(**props),
        )

    def delete(self, id: str, props: _SSLCertificateProps):
        """Delete an SSL certificate."""
        try:
            # Remove the DNS record
            azure_api = AzureApi(props["subscription_name"])
            azure_api.remove_dns_txt_record(
                record_name="_acme_challenge",
                resource_group_name=props["networking_resource_group_name"],
                zone_name=props["domain_name"],
            )
            # Remove the Key Vault certificate
            azure_api.remove_keyvault_certificate(
                certificate_name=props["certificate_secret_name"],
                key_vault_name=props["key_vault_name"],
            )
        except Exception as exc:
            raise DataSafeHavenSSLException(
                f"Failed to delete SSL certificate <fg=green>{props['certificate_secret_name']}</> for <fg=green>{props['domain_name']}</>."
            ) from exc

    def diff(
        self,
        id: str,
        oldProps: _SSLCertificateProps,
        newProps: _SSLCertificateProps,
    ) -> DiffResult:
        """Calculate diff between old and new state"""
        # List any values that were not present in oldProps or have been changed
        altered_props = [
            property
            for property in dict(newProps).keys()
            if (property not in oldProps) or (oldProps[property] != newProps[property])
        ]
        return DiffResult(
            changes=True,  # (altered_props != []),  # changes are needed
            replaces=[],  # replacement is needed
            stables=None,  # list of inputs that are constant
            delete_before_replace=True,  # delete the existing resource before replacing
        )

    def update(
        self,
        id: str,
        oldProps: _SSLCertificateProps,
        newProps: _SSLCertificateProps,
    ) -> DiffResult:
        """Updating is deleting followed by creating."""
        # Note that we need to use the auth token from newProps
        self.delete(id, oldProps)
        updated = self.create(newProps)
        return UpdateResult(outs={**updated.outs})


class SSLCertificate(Resource):
    def __init__(
        self,
        name: str,
        props: SSLCertificateProps,
        opts: Optional[ResourceOptions] = None,
    ):
        self._resource_type_name = "ssl:SSLCertificate"  # set resource type
        super().__init__(
            SSLCertificateProvider(),
            name,
            {**vars(props)},
            opts,
        )
