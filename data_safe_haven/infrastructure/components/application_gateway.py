# Standard library imports
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources


class ApplicationGatewayProps:
    """Properties for ApplicationGatewayComponent"""

    def __init__(
        self,
        hostname_guacamole: Input[str],
        ip_address_guacamole: Input[str],
        key_vault_certificate_id: Input[str],
        key_vault_identity: Input[str],
        resource_group_name: Input[str],
        virtual_network: Input[network.VirtualNetwork],
        subnet_name: Optional[Input[str]] = "ApplicationGatewaySubnet",
    ):
        self.hostname_guacamole = hostname_guacamole
        self.key_vault_certificate_id = key_vault_certificate_id
        self.key_vault_identity = key_vault_identity
        self.ip_address_guacamole = ip_address_guacamole
        self.resource_group_name = resource_group_name
        self.subnet_name = subnet_name
        self.virtual_network = virtual_network


class ApplicationGatewayComponent(ComponentResource):
    """Deploy application gateway with Pulumi"""

    def __init__(
        self, name: str, props: ApplicationGatewayProps, opts: ResourceOptions = None
    ):
        super().__init__(
            "dsh:application_gateway:ApplicationGatewayComponent", name, {}, opts
        )
        child_opts = ResourceOptions(parent=self)

        # Retrieve existing resource group and subnet
        resource_group = resources.get_resource_group(props.resource_group_name)
        snet_application_gateway = network.get_subnet_output(
            subnet_name="ApplicationGatewaySubnet",
            resource_group_name=props.resource_group_name,
            virtual_network_name=props.virtual_network.name,
        )

        # Define public IP address
        public_ip = network.PublicIPAddress(
            "ag_public_ip",
            public_ip_address_name=f"ag-{self._name}-public-ip",
            public_ip_allocation_method="Static",
            resource_group_name=props.resource_group_name,
            sku=network.PublicIPAddressSkuArgs(name="Standard"),
            opts=child_opts,
        )

        # Define application gateway
        application_gateway_name = f"ag-{self._name}-entrypoint"
        application_gateway = network.ApplicationGateway(
            "application_gateway",
            application_gateway_name=application_gateway_name,
            backend_address_pools=[
                network.ApplicationGatewayBackendAddressPoolArgs(
                    backend_addresses=[
                        network.ApplicationGatewayBackendAddressArgs(
                            ip_address=props.ip_address_guacamole
                        )
                    ],
                    name="appGatewayBackendGuacamole",
                ),
            ],
            backend_http_settings_collection=[
                network.ApplicationGatewayBackendHttpSettingsArgs(
                    name="appGatewayBackendHttpSettings",
                    port=80,
                    protocol="Http",
                    request_timeout=30,
                ),
            ],
            frontend_ip_configurations=[
                network.ApplicationGatewayFrontendIPConfigurationArgs(
                    name="appGatewayFrontendIP",
                    private_ip_allocation_method="Dynamic",
                    public_ip_address=network.SubResourceArgs(id=public_ip.id),
                )
            ],
            frontend_ports=[
                network.ApplicationGatewayFrontendPortArgs(
                    name="appGatewayFrontendHttp",
                    port=80,
                ),
                network.ApplicationGatewayFrontendPortArgs(
                    name="appGatewayFrontendHttps",
                    port=443,
                ),
            ],
            gateway_ip_configurations=[
                network.ApplicationGatewayIPConfigurationArgs(
                    name="appGatewayIP",
                    subnet=network.SubResourceArgs(id=snet_application_gateway.id),
                )
            ],
            http_listeners=[
                # Guacamole listeners
                network.ApplicationGatewayHttpListenerArgs(
                    frontend_ip_configuration=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/frontendIPConfigurations/appGatewayFrontendIP",
                        )
                    ),
                    frontend_port=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/frontendPorts/appGatewayFrontendHttp",
                        )
                    ),
                    host_name=props.hostname_guacamole,
                    name="GuacamoleHttpListener",
                    protocol="Http",
                ),
                network.ApplicationGatewayHttpListenerArgs(
                    frontend_ip_configuration=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/frontendIPConfigurations/appGatewayFrontendIP",
                        )
                    ),
                    frontend_port=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/frontendPorts/appGatewayFrontendHttps",
                        )
                    ),
                    host_name=props.hostname_guacamole,
                    name="GuacamoleHttpsListener",
                    protocol="Https",
                    ssl_certificate=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/sslCertificates/sslcert",
                        ),
                    ),
                    ssl_profile=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/sslProfiles/sslProfile",
                        ),
                    ),
                ),
            ],
            identity=network.ManagedServiceIdentityArgs(
                type="UserAssigned",
                user_assigned_identities={
                    props.key_vault_identity: {},
                },
            ),
            redirect_configurations=[
                # Guacamole HTTP redirect
                network.ApplicationGatewayRedirectConfigurationArgs(
                    include_path=True,
                    include_query_string=True,
                    name="GuacamoleHttpToHttpsRedirection",
                    redirect_type="Permanent",
                    request_routing_rules=[
                        network.SubResourceArgs(
                            id=Output.concat(
                                resource_group.id,
                                f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/requestRoutingRules/HttpToHttpsRedirection",
                            ),
                        )
                    ],
                    target_listener=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/httpListeners/GuacamoleHttpsListener",
                        )
                    ),
                ),
            ],
            request_routing_rules=[
                # Guacamole routing
                network.ApplicationGatewayRequestRoutingRuleArgs(
                    http_listener=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/httpListeners/GuacamoleHttpListener",
                        )
                    ),
                    redirect_configuration=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/redirectConfigurations/GuacamoleHttpToHttpsRedirection",
                        )
                    ),
                    name="GuacamoleHttpRouting",
                    rule_type="Basic",
                ),
                network.ApplicationGatewayRequestRoutingRuleArgs(
                    backend_address_pool=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/backendAddressPools/appGatewayBackendGuacamole",
                        )
                    ),
                    backend_http_settings=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/backendHttpSettingsCollection/appGatewayBackendHttpSettings",
                        )
                    ),
                    http_listener=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/httpListeners/GuacamoleHttpsListener",
                        )
                    ),
                    name="GuacamoleHttpsRouting",
                    rule_type="Basic",
                ),
            ],
            resource_group_name=props.resource_group_name,
            sku=network.ApplicationGatewaySkuArgs(
                capacity=1,
                name="Standard_v2",
                tier="Standard_v2",
            ),
            ssl_certificates=[
                network.ApplicationGatewaySslCertificateArgs(
                    key_vault_secret_id=props.key_vault_certificate_id,
                    name="sslcert",
                ),
            ],
            ssl_profiles=[
                network.ApplicationGatewaySslProfileArgs(
                    client_auth_configuration=network.ApplicationGatewayClientAuthConfigurationArgs(
                        verify_client_cert_issuer_dn=True,
                    ),
                    name="sslProfile",
                    ssl_policy=network.ApplicationGatewaySslPolicyArgs(
                        # We take the ones recommended by SSL Labs (https://github.com/ssllabs/research/wiki/SSL-and-TLS-Deployment-Best-Practices) excluding any that are unsupported
                        cipher_suites=[
                            "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
                            "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
                            "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
                            "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA",
                            "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256",
                            "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384",
                            "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
                            "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
                            "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA",
                            "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
                            "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256",
                            "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384",
                            "TLS_DHE_RSA_WITH_AES_128_GCM_SHA256",
                            "TLS_DHE_RSA_WITH_AES_256_GCM_SHA384",
                            "TLS_DHE_RSA_WITH_AES_128_CBC_SHA",
                            "TLS_DHE_RSA_WITH_AES_256_CBC_SHA",
                        ],
                        min_protocol_version="TLSv1_1",
                        policy_type="Custom",
                    ),
                )
            ],
            opts=child_opts,
        )

        # Register outputs
        self.public_ip_address = public_ip.ip_address
        self.resource_group_name = Output.from_input(props.resource_group_name)
