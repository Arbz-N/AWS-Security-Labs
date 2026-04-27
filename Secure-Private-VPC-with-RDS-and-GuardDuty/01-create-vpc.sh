#!/bin/bash
# 01-create-vpc.sh
# Creates the full VPC networking stack for the Secure RDS + GuardDuty lab.
# Resources: VPC, 3 subnets (1 public + 2 private), IGW, route table, security group.
#
# Prerequisites: AWS_REGION must be exported before running.
# Usage        : bash 01-create-vpc.sh


# ============================================================
# CONFIG
# ============================================================
AWS_REGION="${AWS_REGION:-your-region}"   # override with: export AWS_REGION=us-east-1
VPC_CIDR="10.0.0.0/16"
PUBLIC_CIDR="10.0.1.0/24"
PRIVATE_CIDR_1="10.0.2.0/24"
PRIVATE_CIDR_2="10.0.3.0/24"

# ─────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block "${VPC_CIDR}" \
  --region "${AWS_REGION}" \
  --query 'Vpc.VpcId' \
  --output text)
echo "[OK] VPC created: ${VPC_ID}"

aws ec2 create-tags \
  --resources "${VPC_ID}" \
  --tags Key=Name,Value=secure-lab-vpc

# DNS support is required so that RDS endpoints (DNS names) can be resolved
# from within the VPC. Without this, connections to RDS will fail on lookup.
aws ec2 modify-vpc-attribute \
  --vpc-id "${VPC_ID}" \
  --enable-dns-support

aws ec2 modify-vpc-attribute \
  --vpc-id "${VPC_ID}" \
  --enable-dns-hostnames

echo "[OK] DNS enabled on VPC"

# ─────────────────────────────────────────────
# Subnets
# ─────────────────────────────────────────────

# Public subnet — for internet-facing resources (ALB, bastion, ECS tasks with public IPs).
PUBLIC_SUBNET=$(aws ec2 create-subnet \
  --vpc-id "${VPC_ID}" \
  --cidr-block "${PUBLIC_CIDR}" \
  --availability-zone "${AWS_REGION}a" \
  --query 'Subnet.SubnetId' \
  --output text)
aws ec2 create-tags \
  --resources "${PUBLIC_SUBNET}" \
  --tags Key=Name,Value=public-subnet-1
echo "[OK] Public subnet:   ${PUBLIC_SUBNET}"

# Private subnet 1 — RDS primary instance runs here.
PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id "${VPC_ID}" \
  --cidr-block "${PRIVATE_CIDR_1}" \
  --availability-zone "${AWS_REGION}a" \
  --query 'Subnet.SubnetId' \
  --output text)
aws ec2 create-tags \
  --resources "${PRIVATE_SUBNET_1}" \
  --tags Key=Name,Value=private-subnet-1
echo "[OK] Private subnet 1: ${PRIVATE_SUBNET_1}"

# Private subnet 2 — second AZ required by RDS DB subnet group rules.
# RDS always requires subnets in at least two AZs, even for Single-AZ deployments.
PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id "${VPC_ID}" \
  --cidr-block "${PRIVATE_CIDR_2}" \
  --availability-zone "${AWS_REGION}b" \
  --query 'Subnet.SubnetId' \
  --output text)
aws ec2 create-tags \
  --resources "${PRIVATE_SUBNET_2}" \
  --tags Key=Name,Value=private-subnet-2
echo "[OK] Private subnet 2: ${PRIVATE_SUBNET_2}"

# ─────────────────────────────────────────────
# Internet Gateway and Public Route Table
# ─────────────────────────────────────────────

IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)
aws ec2 attach-internet-gateway \
  --internet-gateway-id "${IGW_ID}" \
  --vpc-id "${VPC_ID}"
echo "[OK] Internet Gateway: ${IGW_ID}"

PUBLIC_RT=$(aws ec2 create-route-table \
  --vpc-id "${VPC_ID}" \
  --query 'RouteTable.RouteTableId' \
  --output text)

# Default route sends all internet traffic through the IGW.
# Only the public subnet is associated with this route table.
# Private subnets use the VPC's implicit main route table, which has
# no route to the internet — this is the security boundary for RDS.
aws ec2 create-route \
  --route-table-id "${PUBLIC_RT}" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "${IGW_ID}"

aws ec2 associate-route-table \
  --route-table-id "${PUBLIC_RT}" \
  --subnet-id "${PUBLIC_SUBNET}"

echo "[OK] Public route table configured: ${PUBLIC_RT}"

# ─────────────────────────────────────────────
# RDS Security Group
# ─────────────────────────────────────────────

RDS_SG=$(aws ec2 create-security-group \
  --group-name rds-security-group \
  --description "RDS Private Security Group" \
  --vpc-id "${VPC_ID}" \
  --query 'GroupId' \
  --output text)
aws ec2 create-tags \
  --resources "${RDS_SG}" \
  --tags Key=Name,Value=rds-sg

# Allow MySQL only from within the VPC CIDR.
# Scoping to the VPC CIDR (not 0.0.0.0/0) ensures only resources inside
# this VPC can attempt a connection — not anything on the public internet.
aws ec2 authorize-security-group-ingress \
  --group-id "${RDS_SG}" \
  --protocol tcp \
  --port 3306 \
  --cidr "${VPC_CIDR}"

echo "[OK] RDS Security Group: ${RDS_SG}"

# ─────────────────────────────────────────────
# Export variables for use in other scripts
# ─────────────────────────────────────────────
echo ""
echo "[INFO] Copy and export these variables before running the next scripts:"
echo ""
echo "  export VPC_ID=${VPC_ID}"
echo "  export PUBLIC_SUBNET=${PUBLIC_SUBNET}"
echo "  export PRIVATE_SUBNET_1=${PRIVATE_SUBNET_1}"
echo "  export PRIVATE_SUBNET_2=${PRIVATE_SUBNET_2}"
echo "  export IGW_ID=${IGW_ID}"
echo "  export PUBLIC_RT=${PUBLIC_RT}"
echo "  export RDS_SG=${RDS_SG}"
echo ""
echo "[OK] VPC stack created successfully."