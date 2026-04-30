# AWS MFA Enforcement, IAM Hardening, and Control Tower Setup:


    Overview
        This lab establishes a foundational AWS security posture covering four areas:
        MFA enforcement for root and IAM users, a deny-without-MFA IAM policy,
        a strong account-wide password policy, and AWS Control Tower with guardrails
        and account factory provisioning.
        Key highlights:
        
        Root account MFA enabled via Virtual MFA (Authenticator app)
        IAM user MFA enforced through an explicit Deny policy that blocks all actions
        unless aws:MultiFactorAuthPresent is true
        Account-wide password policy: 14-character minimum, symbols required,
        90-day rotation, 12-password reuse prevention
        Control Tower landing zone with Log Archive and Audit dedicated accounts
        Guardrails detecting MFA gaps, public S3, and root access key creation
        Account Factory creating new accounts with security baseline pre-applied

## Project Structure:

    AWS-MFA-Enforcement-IAM-Hardening-and-Control-Tower-Setup/
    ├── README.md                      <- This file
    ├── 01-check-mfa-status.sh         <- List users and their MFA device status
    ├── 02-create-mfa-policy.sh        <- Create and attach the ForceMFAPolicy
    ├── mfa-enforce-policy.json        <- IAM policy document (deny without MFA)
    ├── 03-set-password-policy.sh      <- Apply account-wide password policy
    ├── 04-generate-credential-report.sh <- MFA audit across all users
    └── cleanup.sh                     <- Remove MFA devices, policy, and detach

## Prerequisites:

    Requirement          Details
    
    AWS Account          Management or root account
    Root credentials     Email + password for the management account
    MFA app              Google Authenticator or compatible TOTP app on a phone
    AWS Organizations    Must be enabled before Control Tower setup
    AWS CLI              Configured with admin credentials
    IAM permissions      Full IAM, Control Tower, and Organizations access

## Architecture:

    Management Account
      +------------------------------------------------------------------+
      |                                                                  |
      |  Root Account                                                    |
      |    MFA: Virtual MFA (Authenticator app)  [REQUIRED FIRST]        |
      |                                                                  |
      |  IAM Users                                                       |
      |    arbaz      MFA: Virtual MFA                                   |
      |    developer  MFA: Virtual MFA                                   |
      |                                                                  |
      |  ForceMFAPolicy (attached to users / group)                      |
      |    Allow: IAM self-service MFA setup actions                     |
      |    Deny:  ALL other actions if MFA not present                   |
      |                                                                  |
      |  Password Policy                                                 |
      |    Min length: 14   Symbols: required   Rotation: 90 days        |
      |    Reuse prevention: 12 passwords                                |
      +------------------------------------------------------------------+
    
      AWS Control Tower (landing zone)
      +------------------------------------------------------------------+
      |  Management Account (existing)                                   |
      |  Log Archive Account  (new — dedicated for all logs)             |
      |  Audit Account        (new — security team access)               |
      |                                                                  |
      |  Guardrails (mandatory + strongly recommended):                  |
      |    Detect: MFA not enabled for IAM users                         |
      |    Detect: Public S3 access allowed                              |
      |    Detect: Root account MFA missing                              |
      |    Prevent: Root access key creation                             |
      |                                                                  |
      |  Account Factory                                                 |
      |    dev-workloads account — auto-enrolled with baseline           |
      +------------------------------------------------------------------+
    
      MFA Login Flow:
        User -> AWS Console Login Page
             -> Username + Password
             -> MFA Prompt (6-digit TOTP)
             -> TOTP validated by AWS
             -> Session token with MultiFactorAuthPresent=true
             -> Full access granted

## Step-by-Step Tasks:

### Task 1 — Enable MFA for the Root Account

    [WARN] Complete this task before any other task. The root account has
    unrestricted access to everything in the AWS account. Protecting it with
    MFA is the single most important security action.

    Steps (AWS Console only — root MFA cannot be set via CLI):

        Sign in to the AWS Console as root (email + password).
        Top right corner: click the account name → Security credentials.
        Find the Multi-factor authentication (MFA) section.
        Click Assign MFA device.
        Select Authenticator app (Virtual MFA).
        Device name: RootAccountMFA → Next.
        Open Google Authenticator on your phone → + → Scan QR code.
        Scan the QR code shown on screen.
        Enter MFA code 1 from the app, wait 30 seconds, enter MFA code 2.
        Click Add MFA.

    [WARN] Screenshot the QR code or copy the secret key and store it securely
    offline. If you lose the phone, this backup is the only way to recover access.
    
    Verify:
    
        Sign out of the console.
        Sign back in: email → password → 6-digit MFA code from the app.
        Successful login confirms MFA is working.

### Task 2 — Enable MFA for IAM Users:

    Steps (AWS Console):

        Go to IAM → Users and click a user (e.g. arbaz).
        Click the Security credentials tab.
        In the Multi-factor authentication section, click Assign MFA device.
        Device name: arbaz-mfa-device → select Authenticator app → Next.
        Scan the QR code with Google Authenticator.
        Enter two consecutive 6-digit codes → Add MFA.

    Verify via CLI:

    bash 01-check-mfa-status.sh
    
    The script lists all users and runs list-mfa-devices to confirm each user
    has a device registered.

### Task 3 — Enforce MFA via IAM Policy:

    See mfa-enforce-policy.json and 02-create-mfa-policy.sh.

    bash 02-create-mfa-policy.sh

    What the policy does:
    AllowViewAccountInfo   : Allow viewing account password policy and MFA device list
    AllowManageOwnMFA      : Allow each user to set up their own MFA device
    DenyAllExceptMFASetup  : Deny every other action when MultiFactorAuthPresent=false

    The DenyAllExceptMFASetup statement uses NotAction — it applies to
    every action in AWS except the MFA setup actions listed. This means a user
    without MFA enabled can only set up their own MFA and nothing else.

    [INFO] Attach this policy to a group rather than individual users so it
    applies automatically to all new users added to the group.

### Task 4 — Set Up AWS Control Tower:

    Prerequisites before starting:
    
        AWS Organizations must be enabled in the management account.
        The management account must not already have Config or CloudTrail customizations
        that would conflict with Control Tower baseline setup.

    Steps (AWS Console — 30 to 60 minutes):

        Go to AWS Console → Control Tower → Set up landing zone.
        Home Region: select your primary region (e.g. your-region).
        Log Archive Account: provide a unique email address (e.g. log-archive@yourcompany.com).
        Audit Account: provide a unique email address (e.g. audit@yourcompany.com).
        Review all settings → click Set up landing zone.


    [WARN] Do not close the browser during setup. The process takes 30 to 60 minutes.

    Expected result after setup:

    Management Account    (existing)   enrolled
    Log Archive Account   (new)        all CloudTrail and Config logs aggregated here
    Audit Account         (new)        read-only access for security team

### Task 5 — Enable Guardrails:

    Steps (AWS Console — Control Tower → Guardrails):
    
        Enable the following strongly recommended guardrails:
        [OK] Detect whether MFA is enabled for IAM users
        [OK] Detect whether public access to S3 is allowed
        [OK] Detect whether root account has MFA enabled
        [OK] Disallow creation of access keys for root user

    Verify via CLI:
    bash# Replace the target ARN with your Organizations root ARN

        aws controltower list-enabled-controls \
          --target-identifier "arn:aws:organizations::your-account-id:root/r-xxxx" \
          --output table

Task 6 — Provision a New Account via Account Factory:

    Steps (AWS Console — Control Tower → Account Factory → Create account):

        Account name    : dev-workloads
        Account email   : dev@yourcompany.com
        Display name    : Development Account
        IAM Identity    : dev-admin
        OU              : (select an existing OU or create a Custom OU)

    Click Create account. The process takes 15 to 20 minutes.
    
        The new account is automatically enrolled with:
        CloudTrail enabled
        AWS Config rules configured
        Guardrails applied
        Security baseline pre-installed

Task 7 — Set IAM Account Password Policy:
    
    See 03-set-password-policy.sh.

        bash 03-set-password-policy.sh
        The script enforces:
        Minimum length          : 14 characters
        Require symbols         : yes
        Require numbers         : yes
        Require uppercase       : yes
        Require lowercase       : yes
        Max password age        : 90 days
        Password reuse prevent  : 12 previous passwords
        Users change password   : allowed
        Hard expiry             : disabled (locked out = false)

Task 8 — Verify MFA Status Across All Users:

See 04-generate-credential-report.sh.

    bash 04-generate-credential-report.sh
    
        The script generates an IAM credential report and extracts the mfa_active
        column for every user. Any user showing false does not have MFA enabled.

    Manual login test:
        
        Sign out of the AWS Console.
        Sign in: Account ID → Username → Password → Next.
        The MFA prompt should appear: Enter authentication code.
        Enter the 6-digit code from the Authenticator app.
        Successful login confirms the full MFA flow is working end to end.

Key Concepts:


    Why MFA on root first?

        The root account bypasses all IAM policies. It can close the account, remove
        Organization SCPs, and access billing data regardless of what IAM policies say.
        Any attacker with root credentials has unrestricted control. MFA is the only
        additional authentication factor that protects root, since you cannot attach
        IAM policies to root.

    How the ForceMFAPolicy works:

        The policy uses an explicit Deny with BoolIfExists: aws:MultiFactorAuthPresent: false.
        BoolIfExists is used rather than Bool so that the condition applies even
        when the key is absent from the request context (e.g. during long-term credential
        use without a session token). The NotAction list gives the user just enough
        access to set up their own MFA before the Deny blocks everything else.

    Why NotAction instead of Action in the Deny statement
    
        Action: Deny: * with a condition would also block the MFA setup actions,
        creating a deadlock where a user with no MFA cannot enable MFA. Using NotAction
        with the MFA setup actions listed exempts exactly those actions from the Deny,
        allowing new users to complete MFA enrollment before being fully restricted.

    What Control Tower guardrails actually enforce

        Guardrails are implemented as either SCPs (Service Control Policies) for
        preventive controls or AWS Config rules for detective controls. Preventive
        guardrails block the API action at the Organizations level — even account
        admins cannot bypass them. Detective guardrails report compliance status but
        do not block the action.

    Why Account Factory accounts get a security baseline automatically

        Control Tower uses AWS Service Catalog behind the scenes. When Account Factory
        creates an account, it enrolls it into the landing zone by applying a
        CloudFormation StackSet that deploys CloudTrail, Config, and the guardrail
        SCP inheritance from the Organization. This baseline is applied to every new
        account regardless of who creates it.

    What the credential report reveals

        The IAM credential report is a CSV generated by AWS that lists every IAM user
        along with password age, access key ages, last use dates, and MFA status.
        The mfa_active column is the fastest way to identify users without MFA across
        the entire account without checking each user individually.

Cleanup:

    bash cleanup.sh

        The script performs:
        1. Deactivate MFA device for the user
           2. Delete the virtual MFA device
           3. Detach ForceMFAPolicy from the user
           4. Delete the ForceMFAPolicy
           Control Tower removal (manual — AWS Console):

    [WARN] Control Tower landing zone deletion is irreversible and complex.
    Complete these steps before deleting the landing zone:

    Unenroll all accounts created via Account Factory.
    Manually close or unenroll the Log Archive and Audit accounts.
    Go to Control Tower → Landing zone settings → Delete landing zone.
    Confirm the deletion.
    
    Deleting the landing zone does not close the sub-accounts. Those must be
    closed separately through AWS Organizations or the Accounts console.

License:

    MIT License. This lab is for educational purposes.
    Replace all placeholder values (your-account-id, your-region,
    arbaz, your-key-pair, email addresses) before sharing or committing.
    Never commit real account IDs, ARNs, or credentials to version control.