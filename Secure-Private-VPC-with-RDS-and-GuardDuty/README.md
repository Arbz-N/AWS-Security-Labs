# Secure Private VPC with RDS and GuardDuty:

    Overview
    This lab builds a private, security-hardened AWS environment consisting of a custom
    VPC with public and private subnets, a MySQL RDS instance isolated in private subnets,
    and AWS GuardDuty enabled with RDS and S3 protection plans.
    Key highlights:
    
    VPC with 1 public subnet and 2 private subnets across two Availability Zones
    RDS MySQL 8.0 with no public access, storage encryption, and 7-day backup retention
    Security Group restricts MySQL port 3306 to VPC CIDR only (no 0.0.0.0/0)
    GuardDuty monitoring CloudTrail, VPC Flow Logs, DNS logs, RDS login events, and S3 events
    Sample findings generated to verify GuardDuty is functioning before real threats occur

## Project Structure:

    secure-vpc-rds-guardduty-lab/
    ├── README.md                  <- This file
    ├── 01-create-vpc.sh           <- VPC, subnets, IGW, route table, security group
    ├── 02-enable-guardduty.sh     <- GuardDuty detector + protection plans
    ├── 03-create-rds-subnet.sh    <- DB subnet group creation
    ├── 04-verify-guardduty.sh     <- Sample findings + list findings
    └── cleanup.sh                 <- Full teardown in dependency order

## Prerequisites:

    Requirement          Details
    
    AWS Account          IAM Admin access required
    AWS CLI              Installed and configured (aws configure)
    AWS Region           Any region with RDS + GuardDuty support
    Permissions          EC2, RDS, GuardDuty, IAM


## Architecture:

        Region: your-region
          +-------------------------------------------------------------------+
          |  VPC: secure-lab-vpc (10.0.0.0/16)                                |
          |                                                                   |
          |  +----------------------+    +--------------------------------+   |
          |  | Public Subnet        |    | Private Subnet 1 (AZ-a)       |    |
          |  | 10.0.1.0/24          |    | 10.0.2.0/24                   |    |
          |  | (AZ-a)               |    |                               |    |
          |  |                      |    |  +-------------------------+  |    |
          |  |  Internet-facing     |    |  | RDS MySQL 8.0           |  |    |
          |  |  resources (ECS,     |    |  | secure-rds-lab          |  |    |
          |  |  ALB, Bastion etc.)  |    |  | Encrypted + No Public   |  |    |
          |  +----------+-----------+    |  | Access                  |  |    |
          |             |                |  +-------------------------+  |    |
          |             |                +--------------------------------+   |
          |  +----------+-----------+                                         |
          |  | Internet Gateway     |    +--------------------------------+   |
          |  | (public subnet only) |    | Private Subnet 2 (AZ-b)       |    |
          |  +----------------------+    | 10.0.3.0/24                   |    |
          |                              |                               |    |
          |                              |  (RDS Multi-AZ standby)       |    |
          |                              +--------------------------------+   |
          |                                                                   |
          |  Security Group: rds-sg                                           |
          |    Inbound: TCP 3306 from 10.0.0.0/16 only                        |
          |    No inbound from 0.0.0.0/0                                      |
          +-------------------------------------------------------------------+
        
          GuardDuty
          +-------------------------------------------+
          |  Detector (enabled)                        |
          |  Monitors:                                 |
          |   - CloudTrail Management Events           |
          |   - VPC Flow Logs                          |
          |   - DNS Query Logs                         |
          |   - RDS_LOGIN_EVENTS (protection plan)     |
          |   - S3_DATA_EVENTS   (protection plan)     |
          +-------------------------------------------+

## Step-by-Step Tasks:

    Prerequisites
    
    bash# Verify credentials
    aws sts get-caller-identity
    
    # Export variables — all scripts depend on these
    export AWS_REGION="your-region"
    export PROJECT="SecureECSLab"

### Task 1 — Create the Private VPC:

    See 01-create-vpc.sh — this script creates all networking resources in order.
    
    What gets created:
    VPC         10.0.0.0/16        secure-lab-vpc
    Subnet 1    10.0.1.0/24 (AZ-a) public-subnet-1   (public route to IGW)
    Subnet 2    10.0.2.0/24 (AZ-a) private-subnet-1  (no internet access)
    Subnet 3    10.0.3.0/24 (AZ-b) private-subnet-2  (no internet access)
    IGW         attached to VPC
    Route Table 0.0.0.0/0 -> IGW   associated with public subnet only
    SG          rds-sg              TCP 3306 from 10.0.0.0/16
    
    [INFO] Private subnets have no route to the internet by design. This is the
    core security boundary — RDS can only be reached from within the VPC.
    
    
    [WARN] The RDS security group allows MySQL only from the VPC CIDR
    (10.0.0.0/16), not from 0.0.0.0/0. Do not change this to 0.0.0.0/0.

    bash 01-create-vpc.sh

### Task 2 — Enable GuardDuty:

    See 02-enable-guardduty.sh.
    What gets enabled:
    GuardDuty Detector         Monitors CloudTrail, VPC Flow Logs, DNS
    RDS_LOGIN_EVENTS           Detects anomalous RDS authentication attempts
    S3_DATA_EVENTS             Detects unusual S3 access patterns
    bash 02-enable-guardduty.sh
    
    # Save the detector ID — needed for Tasks 4 and cleanup
    export DETECTOR_ID=$(aws guardduty list-detectors \
      --region $AWS_REGION \
      --query 'DetectorIds[0]' \
      --output text)
    echo "Detector ID: $DETECTOR_ID"

### Task 3 — Create RDS in Private Subnets:
    
    Step 3.1 — Create the DB subnet group:
    
    bash 03-create-rds-subnet.sh
    
    Step 3.2 — Create the RDS instance (AWS Console):
    
    Go to RDS > Create database and use these settings:
    Engine          : MySQL Community  8.0.x
    Template        : Free Tier
    Identifier      : secure-rds-lab
    Master username : admin
    Master password : (choose a strong password, minimum 8 characters)
    Instance class  : db.t3.micro
    Storage type    : gp2
    Storage         : 20 GB
    Autoscaling     : Disabled
    VPC             : secure-lab-vpc
    Subnet group    : private-rds-subnet-group
    Public access   : No              [REQUIRED]
    Security group  : rds-security-group
    Encryption      : Enabled
    Backup retention: 7 days
    
    [WARN] Public access must be set to No. An RDS instance with public access
    enabled in a private subnet still accepts connections from the internet
    if the security group allows it.

    Verify the instance after creation (~10 minutes):
    
    aws rds describe-db-instances \
      --db-instance-identifier secure-rds-lab \
      --query 'DBInstances[0].{
        Status:DBInstanceStatus,
        Public:PubliclyAccessible,
        Encrypted:StorageEncrypted,
        Endpoint:Endpoint.Address
      }' \
      --output table
    # [OK] Public should be False, Encrypted should be True

Task 4 — View GuardDuty Findings:

    See 04-verify-guardduty.sh.
    
    bash 04-verify-guardduty.sh
    
    This script generates sample findings of these types:
    Recon:EC2/PortProbeUnprotectedPort
    UnauthorizedAccess:EC2/SSHBruteForce
    Then retrieves the finding list and prints type, severity, and title
    for the first three findings.
    
    [INFO] Sample findings are clearly marked as SAMPLE in the GuardDuty console.
    They do not represent real threats in your account.

### Key Concepts:
    
    Why two private subnets in different AZs?
    RDS requires a DB subnet group with subnets in at least two Availability Zones.
    This is true even for Single-AZ deployments. Multi-AZ failover also depends on
    having a subnet in a second AZ where the standby replica can run.
    
    Why DNS must be enabled on the VPC
    The RDS endpoint is a DNS name (e.g. secure-rds-lab.xxxx.us-east-1.rds.amazonaws.com).
    Without enableDnsSupport and enableDnsHostnames set on the VPC, the endpoint
    cannot be resolved from inside the VPC, and connections will fail even from
    resources that are in the correct subnet.
    
    Why the security group uses the VPC CIDR instead of 0.0.0.0/0
    Using 0.0.0.0/0 on port 3306 would allow any IP address on the internet to
    attempt a MySQL connection if the RDS instance ever became reachable. Scoping
    the inbound rule to 10.0.0.0/16 means only resources inside this VPC can even
    initiate a connection attempt.
    
    What GuardDuty actually monitors
    GuardDuty is agentless — it analyzes existing AWS data sources. The base
    detector reads CloudTrail management events (API calls), VPC Flow Logs (network
    traffic records), and DNS query logs (outbound DNS from EC2). The protection
    plans extend this to RDS authentication logs and S3 data access events. No
    agents or log forwarding configuration is required.
    
    Why RDS_LOGIN_EVENTS is a separate protection plan
    GuardDuty's base detector does not monitor RDS authentication by default.
    The RDS protection plan is a separately billable feature that ingests RDS login
    activity logs. Enabling it allows GuardDuty to detect findings such as
    CredentialAccess:RDS/AnomalousBehavior.SuccessfulLogin.
    
    Cleanup order dependency
    VPC resources must be deleted in reverse dependency order. An RDS instance
    holds a reference to the subnet group. The subnet group holds references to
    the subnets. The route table association must be removed before the route table
    can be deleted. The IGW must be detached before it can be deleted. The VPC
    cannot be deleted while any of these resources still exist inside it.

### Cleanup:

    See cleanup.sh. Run it from the same shell session where variables are still exported.

    bash cleanup.sh

    The script deletes resources in this order:
    1. RDS instance (waits for full deletion before proceeding)
       2. DB Subnet Group
       3. GuardDuty Detector
       4. RDS Security Group
       5. Route Table association
       6. Route Table
       7. Internet Gateway (detach then delete)
       8. Public Subnet
       9. Private Subnet 1
       10. Private Subnet 2
       11. VPC
    
    [WARN] The RDS deletion uses --skip-final-snapshot. All data is permanently
    destroyed. Do not run cleanup on any database you want to keep.


### License:
    
    MIT License. This lab is for educational purposes.
    Replace all placeholder values (your-region, your-account-id, passwords)
    before sharing or committing this project. Never commit real credentials.