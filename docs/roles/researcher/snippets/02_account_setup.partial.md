## {{rocket}} Set up your account

This section of the user guide will help you set up your new account on the SRE you'll be using.

### {{seedling}} Prerequisites

Make sure you have all of the following in front of you when connecting to the SRE.

- {{email}} The email from your {ref}`System Manager <role_system_manager>` with your account details.
- {{wrench}} Your [username](#username), given in an email from your {ref}`System Manager <role_system_manager>`.
- {{european_castle}} The [domain name and URL](#domain-names) for the SRE, given in an email from your {ref}`System Manager <role_system_manager>`.
- {{computer}} Your computer.
- {{satellite}} [Access](#network-access) to the specific wired or wireless network detailed in the email from your {ref}`System Manager <role_system_manager>`.
- {{lock}} [Data security training](#data-security-training-requirements) for those working on health datasets.
- {{iphone}} Your [phone](#your-phone-for-multi-factor-authentication), with good signal connectivity.

You should also know who the **designated contact** for your SRE is.
This might be an administrator or one of the people working on the project with you.
They will be your primary point of contact if you have any issues in connecting to or using the SRE.

```{note}
For example, during the Turing Data Study Groups, the **facilitator** of each SRE is the designated contact
```

#### Username

Your username will usually be in the format `firstname.lastname`.
In some places, you will need to enter it in the form `username@<username domain>`

```{tip}
You can find your username in the email you received from your {ref}`System Manager <role_system_manager>`.
```

```{caution}
If you have a hyphenated last name, or multiple surnames, or a long family name, your assigned username may not follow the same pattern of `firstname.lastname`.
Please check with the designated contact for your SRE if you are unsure about your username.
```

```{note}
In this document we will use **Ada Lovelace** as our example user.
Her username is:
- short-form: `ada.lovelace`
- long-form: `ada.lovelace@projects.turingsafehaven.ac.uk`
```

#### Network access

The SRE that you're using may be configured to allow access only from a specific set of IP addresses.
This may involve being connected to a specific wired or wireless network or using a VPN.
You also may be required to connect from a specific, secure location.
You will be told what these requirements are for your particular environment.

```{tip}
Make sure you know the networks from which you must connect to your SRE.
This information will be available in the email you received with your connection information.
```

#### Data security training requirements

Depending on your project, you may be required to undertake {ref}`data security awareness training <process_data_security_training>`.

```{tip}
Check with your designated contact to see whether this is the case for you.
```

#### Your phone for multi-factor authentication

Multi-factor authentication (MFA) is one of the most powerful ways of verifying user identity online.
We therefore use MFA to protect the project data - specifically, we will use your phone number.

```{important}
Make sure to have your phone with you and that you have good signal connectivity when you are connecting to the SRE.
```

```{caution}
You may encounter some connectivity challenges if your phone network has poor connectivity.
The SRE is not set up to allow you to authenticate through other methods.
```

#### Domain names

You should be given the {ref}`username domain <user_guide_username_domain>` in the initial email from your {ref}`System Manager <role_system_manager>`.
You might receive the {ref}`SRE URL <user_guide_sre_url>` at this time, or you might be assigned to a particular SRE at a later point.

```{note}
In this document Ada Lovelace - our example user - will be participating in the `sandbox` project at a Turing Data Study Group.
- Her **{ref}`username domain <user_guide_username_domain>`** is `projects.turingsafehaven.ac.uk` .
- Her **{ref}`SRE URL <user_guide_sre_url>`** is `https://sandbox.projects.turingsafehaven.ac.uk`
```

### {{closed_lock_with_key}} Set a password

For security reasons, you must reset your password before you log in for the first time.
Please follow these steps carefully.

- Open a private/incognito browser session on your computer.

  ```{tip}
  One of the most common problems that users have in connecting to the SRE is automatic completion of usernames and passwords from other accounts on their computer.
  This can be quite confusing, particularly for anyone who logs into Microsoft services for work or personal use.
  ```

  ```{caution}
  Look out for usernames or passwords that are automatically completed, and make sure that you're using the correct details needed to access the SRE.
  ```

- Navigate to the following URL in your browser: `https://aka.ms/mfasetup` .
  This short link starts the process of logging into your account.

- At the login prompt enter `username@<username domain>` and confirm/proceed.
  Remember that your username will probably be in the format `firstname.lastname` .

  ```{note}
  Our example user, Ada Lovelace, participating in the `sandbox` project at a Turing Data Study Group, would enter `ada.lovelace@projects.turingsafehaven.ac.uk`
  ```

- There will then be a password prompt.

  The first time you log in you need to click **"Forgotten my password"**.

  ```{image} user_guide/account_setup_forgotten_password.png
  :alt: Forgotten my password
  :align: center
  ```

  ```{caution}
  If you reset your password, you will need to wait 5-10 mins before logging in again, to allow the user management system to sync up with the new password.
  ```

- Fill out the requested CAPTCHA (your username should be pre-filled).

  ```{image} user_guide/account_setup_captcha.png
  :alt: CAPTCHA
  :align: center
  ```

- Confirm your phone number, which you provided to the {ref}`System Manager <role_system_manager>` when you registered for access to the environment.

  ```{image} user_guide/account_setup_verify_phone.png
  :alt: Verify phone number
  :align: center
  ```

- Select a password.

  Your password must comply with the following requirements:

  ```{important}
  - alphanumeric
  - minimum 12 characters
  - at least one each of:
    - {{input_latin_uppercase}} uppercase character
    - {{input_latin_lowercase}} lowercase character
    - {{input_numbers}} number
  - you should choose a unique password for the SRE to ensure it is secure
  ```

  ```{caution}
  Do not use special characters or symbols in your password!
  The virtual keyboard inside the SRE may not be the same as your physical keyboard and this can make it difficult to type some symbols.
  ```

  Note that this will also ensure that it passes the [Microsoft Azure AD password requirements](https://docs.microsoft.com/en-us/azure/active-directory/authentication/concept-sspr-policy).

  ```{tip}
  We recommend using a password generator [like this one](https://bitwarden.com/password-generator/) to create a password that meets these requirements.
  This will ensure that the password is different from any others that you might use and that it is unlikely to be on any list of commonly used passwords.
  ```

  If your password is too difficult to memorise, we recommend using a password manager, for example [BitWarden](https://bitwarden.com) or [LastPass](https://www.lastpass.com/), to store it securely.

- Enter your password into the `Enter new password` and `Confirm new password` fields.

  ```{image} user_guide/account_setup_new_password.png
  :alt: New password
  :align: center
  ```

- Then continue to the next step

  ```{image} user_guide/account_setup_new_password_sign_in.png
  :alt: Click to continue
  :align: center
  ```

- Log into your account when prompted and at this point you will be asked for additional security verification.

  ```{image} user_guide/account_setup_more_information_required.png
  :alt: Click to continue
  :align: center
  ```

### {{door}} Set up multi-factor authentication

The next step in setting up your account is to authenticate your account from your phone.
This additional security verification is to make it harder for people to impersonate you and connect to the environment without permission.
This is known as multi-factor authentication (MFA).

#### {{telephone_receiver}} Phone number registration

- In order to set up MFA you will need to enter your phone number

  ```{image} user_guide/account_setup_mfa_additional_security_verification.png
  :alt: Additional security verification
  :align: center
  ```

- Once you click next you will receive a phone call straight away.

  ```{image} user_guide/account_setup_mfa_verifying_phone.png
  :alt: Verifying phone number
  :align: center
  ```

  ```{tip}
  The call might say _press the pound key_ or _press the hash key_ both mean hit the `#` button.
  ```

- After following the instructions you will see the following screen

  ```{image} user_guide/account_setup_mfa_verified_phone.png
  :alt: Verified phone number
  :align: center
  ```

- Click `Next` to register this phone number for MFA

  ```{image} user_guide/account_setup_mfa_registered_phone.png
  :alt: Registered phone number
  :align: center
  ```

- You should now see the Security Information dashboard that lists all your verified MFA methods

  ```{image} user_guide/account_setup_mfa_dashboard_phone_only.png
  :alt: Registered phone number
  :align: center
  ```

#### {{iphone}} Authenticator app registration

- If you want to use the Microsoft Authenticator app for MFA (which will work if you have wifi but no phone signal) then click on `+ Add sign-in method` and select `Authenticator app`

  ```{image} user_guide/account_setup_mfa_add_authenticator_app.png
  :alt: Add Authenticator app
  :align: center
  ```

- This will prompt you to download the `Microsoft Authenticator` phone app.

  ```{image} user_guide/account_setup_mfa_download_authenticator_app.png
  :alt: Add Authenticator app
  :align: center
  ```

- You can click on the link in the prompt or follow the appropriate link for your phone here:
  - {{apple}} iOS: `https://bit.ly/iosauthenticator`
  - {{robot}} Android: `https://bit.ly/androidauthenticator`
  - {{bento_box}} Windows mobile: `https://bit.ly/windowsauthenticator`

- You will now be prompted to open the app and:
  - To allow notifications
  - Select `Add an account`
  - Select `Work or School account`

  ```{image} user_guide/account_setup_mfa_allow_notifications.png
  :alt: Allow Authenticator notifications
  :align: center
  ```

  ```{important}
  You must give permission for the authenticator app to send you notifications for the app to work as an MFA method.
  ```

- The next prompt will give you a QR code to scan, like the one shown below
  - Scan the QR code on the screen

  ```{image} user_guide/account_setup_mfa_app_qrcode.png
  :alt: Setup Authenticator app
  :align: center
  ```

- Once this is completed, Microsoft will send you a test notification to respond to

  ```{image} user_guide/account_setup_mfa_authenticator_app_test.png
  :alt: Authenticator app test notification
  :align: center
  ```

- When you click `Approve` on the phone notification, you will get the following message in your browser

  ```{image} user_guide/account_setup_mfa_authenticator_app_approved.png
  :alt: Authenticator app test approved
  :align: center
  ```

- You should now be returned to the Security Information dashboard that lists two verified MFA methods

  ```{image} user_guide/account_setup_mfa_dashboard_two_methods.png
  :alt: Registered MFA methods
  :align: center
  ```

- Choose whichever you prefer to be your `Default sign-in methods`.

- You have now finished setting up MFA and you can close your browser

#### Troubleshooting MFA

Sometimes setting up MFA can be problematic.
You may find the following tips helpful:

- {{inbox_tray}} Make sure you allow notifications on your authenticator app.
- {{sleeping}} Check you don't have _Do not Disturb_ mode on.
- {{zap}} You have to be SUPER FAST at acknowledging the notification on your app, since the access codes update every 30 seconds.
- {{confused}} Sometimes just going through the steps again solves the problem
