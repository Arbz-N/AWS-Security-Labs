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

