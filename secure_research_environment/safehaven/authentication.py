import logging
import adal
from msrestazure.azure_active_directory import AADTokenCredentials
from azure.mgmt.resource.subscriptions import SubscriptionClient
from .logutils import emphasised

def get_subscription(subscription_name, credentials=None):
    # Switch to appropriate subscription
    if not credentials:
        credentials = authenticate_device_code()
    subscription_client = SubscriptionClient(credentials)
    subscription = [s for s in subscription_client.subscriptions.list() if s.display_name == subscription_name][0]
    logging.info("Working in subscription: %s", emphasised(subscription.display_name))
    return (subscription, credentials)

def authenticate_device_code(tenant="4395f4a7-e455-4f95-8a9f-1fbaef6384f9", category=None):
    """
    Authenticate the end-user using device auth.
    """
    authority_host_uri = 'https://login.microsoftonline.com'
    authority_uri = authority_host_uri + '/' + tenant
    if category == "keyvault":
        resource_uri = "https://vault.azure.net"
    else:
        resource_uri = 'https://management.core.windows.net/'
    client_id = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'  # Microsoft ID

    context = adal.AuthenticationContext(authority_uri, api_version=None)
    code_prompt = context.acquire_user_code(resource_uri, client_id)
    access_code = code_prompt["message"].split()[-3]
    logging.info("Please open https://microsoft.com/devicelogin in a browser and enter %s to authenticate", emphasised(access_code))

    mgmt_token = context.acquire_token_with_device_code(resource_uri, code_prompt, client_id)
    credentials = AADTokenCredentials(mgmt_token, client_id)
    return credentials