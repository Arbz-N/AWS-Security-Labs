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

Project Structure:

    AWS-MFA-Enforcement-IAM-Hardening-and-Control-Tower-Setup/
    ├── README.md                      <- This file
    ├── 01-check-mfa-status.sh         <- List users and their MFA device status
    ├── 02-create-mfa-policy.sh        <- Create and attach the ForceMFAPolicy
    ├── mfa-enforce-policy.json        <- IAM policy document (deny without MFA)
    ├── 03-set-password-policy.sh      <- Apply account-wide password policy
    ├── 04-generate-credential-report.sh <- MFA audit across all users
    └── cleanup.sh                     <- Remove MFA devices, policy, and detach

Prerequisites:

    Requirement          Details
    
    AWS Account          Management or root account
    Root credentials     Email + password for the management account
    MFA app              Google Authenticator or compatible TOTP app on a phone
    AWS Organizations    Must be enabled before Control Tower setup
    AWS CLI              Configured with admin credentials
    IAM permissions      Full IAM, Control Tower, and Organizations access

Architecture:

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

Step-by-Step Tasks:

Task 1 — Enable MFA for the Root Account

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

Task 2 — Enable MFA for IAM Users:

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

Task 3 — Enforce MFA via IAM Policy:

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