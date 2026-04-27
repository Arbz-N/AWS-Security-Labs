#!/usr/bin/env bash
# 03-create-rds-subnet.sh
# Creates the DB subnet group that RDS requires before instance creation.
# The group must reference subnets in at least two Availability Zones.
#
# Prerequisites:
#   PRIVATE_SUBNET_1 and PRIVATE_SUBNET_2 must be exported from 01-create-vpc.sh
# Usage: bash 03-create-rds-subnet.sh

set -euo pipefail

# ============================================================
# CONFIG
# ============================================================
AWS_REGION="${AWS_REGION:-your-region}"
PRIVATE_SUBNET_1="${PRIVATE_SUBNET_1:-subnet-XXXXXXXXXXXXXXXXX}"
PRIVATE_SUBNET_2="${PRIVATE_SUBNET_2:-subnet-XXXXXXXXXXXXXXXXX}"
# ============================================================

echo "[INFO] Creating DB subnet group..."
echo "       Subnet 1 (AZ-a): ${PRIVATE_SUBNET_1}"
echo "       Subnet 2 (AZ-b): ${PRIVATE_SUBNET_2}"

# A DB subnet group tells RDS which subnets it may use for instance placement.
# Two subnets in separate AZs are required — even for Single-AZ RDS.
# For Multi-AZ, RDS places the primary in one AZ and the standby in the other.
aws rds create-db-subnet-group \
  --db-subnet-group-name private-rds-subnet-group \
  --db-subnet-group-description "Private subnets for RDS — AZ-a and AZ-b" \
  --subnet-ids "${PRIVATE_SUBNET_1}" "${PRIVATE_SUBNET_2}" \
  --region "${AWS_REGION}"

echo "[OK] DB subnet group created: private-rds-subnet-group"
echo ""
echo "[INFO] Next: create the RDS instance in the AWS Console."
echo "       Use subnet group: private-rds-subnet-group"
echo "       Use security group: rds-security-group"
echo "       Set Public access: No"