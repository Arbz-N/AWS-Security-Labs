#!/bin/bash

# cleanup.sh
# Deletes all lab resources in reverse dependency order.
# Run from the same shell session where variables were exported,
# OR export them manually before running.
#
# Usage: bash cleanup.sh

set -euo pipefail

# ============================================================
# CONFIG — set these if running in a new shell session
# ============================================================
AWS_REGION="${AWS_REGION:-your-region}"
DETECTOR_ID="${DETECTOR_ID:-}"
VPC_ID="${VPC_ID:-}"
PUBLIC_SUBNET="${PUBLIC_SUBNET:-}"
PRIVATE_SUBNET_1="${PRIVATE_SUBNET_1:-}"
PRIVATE_SUBNET_2="${PRIVATE_SUBNET_2:-}"
IGW_ID="${IGW_ID:-}"
PUBLIC_RT="${PUBLIC_RT:-}"
RDS_SG="${RDS_SG:-}"
# ============================================================

echo "[INFO] Starting cleanup in region: ${AWS_REGION}"

# ─────────────────────────────────────────────
# Step 1 — RDS instance
# Must be deleted first. It holds a reference to the subnet group,
# which in turn holds references to the subnets.
# ─────────────────────────────────────────────
echo "[INFO] Deleting RDS instance: secure-rds-lab..."
aws rds delete-db-instance \
  --db-instance-identifier secure-rds-lab \
  --skip-final-snapshot \
  --region "${AWS_REGION}" 2>/dev/null \
  && echo "[OK] RDS deletion initiated" \
  || echo "[WARN] RDS instance not found — may already be deleted"

# Wait for full deletion before removing the subnet group.
# Without this wait, delete-db-subnet-group fails with InvalidDBSubnetGroupStateFault.
echo "[INFO] Waiting for RDS to finish deleting (this takes 3-5 minutes)..."
aws rds wait db-instance-deleted \
  --db-instance-identifier secure-rds-lab \
  --region "${AWS_REGION}" 2>/dev/null \
  && echo "[OK] RDS deleted" \
  || echo "[WARN] Wait timed out or instance already gone — continuing"

# ─────────────────────────────────────────────
# Step 2 — DB Subnet Group
# ─────────────────────────────────────────────
echo "[INFO] Deleting DB subnet group..."
aws rds delete-db-subnet-group \
  --db-subnet-group-name private-rds-subnet-group \
  --region "${AWS_REGION}" 2>/dev/null \
  && echo "[OK] DB subnet group deleted" \
  || echo "[WARN] DB subnet group not found"

# ─────────────────────────────────────────────
# Step 3 — GuardDuty Detector
# Deleting the detector disables GuardDuty and stops all monitoring.
# ─────────────────────────────────────────────
if [ -z "${DETECTOR_ID}" ]; then
  DETECTOR_ID=$(aws guardduty list-detectors \
    --region "${AWS_REGION}" \
    --query 'DetectorIds[0]' \
    --output text 2>/dev/null || true)
fi

if [ -n "${DETECTOR_ID}" ] && [ "${DETECTOR_ID}" != "None" ]; then
  echo "[INFO] Deleting GuardDuty detector: ${DETECTOR_ID}..."
  aws guardduty delete-detector \
    --detector-id "${DETECTOR_ID}" \
    --region "${AWS_REGION}"
  echo "[OK] GuardDuty disabled"
else
  echo "[WARN] No GuardDuty detector found — skipping"
fi

# ─────────────────────────────────────────────
# Step 4 — Security Group
# Must be deleted before the VPC can be deleted.
# ─────────────────────────────────────────────
if [ -n "${RDS_SG}" ]; then
  echo "[INFO] Deleting security group: ${RDS_SG}..."
  aws ec2 delete-security-group \
    --group-id "${RDS_SG}" \
    --region "${AWS_REGION}" 2>/dev/null \
    && echo "[OK] Security group deleted" \
    || echo "[WARN] Security group not found"
fi

# ─────────────────────────────────────────────
# Step 5 — Route Table Association
# The association must be removed before the route table can be deleted.
# ─────────────────────────────────────────────
if [ -n "${VPC_ID}" ]; then
  echo "[INFO] Removing route table association..."
  ASSOC_ID=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --region "${AWS_REGION}" \
    --query 'RouteTables[?Associations[0].Main!=`true`].Associations[0].RouteTableAssociationId' \
    --output text 2>/dev/null || true)

  if [ -n "${ASSOC_ID}" ] && [ "${ASSOC_ID}" != "None" ]; then
    aws ec2 disassociate-route-table \
      --association-id "${ASSOC_ID}" \
      --region "${AWS_REGION}"
    echo "[OK] Route table association removed"
  fi
fi

# ─────────────────────────────────────────────
# Step 6 — Route Table
# ─────────────────────────────────────────────
if [ -n "${PUBLIC_RT}" ]; then
  echo "[INFO] Deleting route table: ${PUBLIC_RT}..."
  aws ec2 delete-route-table \
    --route-table-id "${PUBLIC_RT}" \
    --region "${AWS_REGION}" 2>/dev/null \
    && echo "[OK] Route table deleted" \
    || echo "[WARN] Route table not found"
fi

# ─────────────────────────────────────────────
# Step 7 — Internet Gateway
# Must be detached from the VPC before it can be deleted.
# ─────────────────────────────────────────────
if [ -n "${IGW_ID}" ] && [ -n "${VPC_ID}" ]; then
  echo "[INFO] Detaching and deleting Internet Gateway: ${IGW_ID}..."
  aws ec2 detach-internet-gateway \
    --internet-gateway-id "${IGW_ID}" \
    --vpc-id "${VPC_ID}" \
    --region "${AWS_REGION}" 2>/dev/null || true
  aws ec2 delete-internet-gateway \
    --internet-gateway-id "${IGW_ID}" \
    --region "${AWS_REGION}" 2>/dev/null \
    && echo "[OK] Internet Gateway deleted" \
    || echo "[WARN] Internet Gateway not found"
fi

# ─────────────────────────────────────────────
# Step 8 — Subnets
# ─────────────────────────────────────────────
for SUBNET_ID in "${PUBLIC_SUBNET:-}" "${PRIVATE_SUBNET_1:-}" "${PRIVATE_SUBNET_2:-}"; do
  if [ -n "${SUBNET_ID}" ]; then
    echo "[INFO] Deleting subnet: ${SUBNET_ID}..."
    aws ec2 delete-subnet \
      --subnet-id "${SUBNET_ID}" \
      --region "${AWS_REGION}" 2>/dev/null \
      && echo "[OK] Subnet deleted: ${SUBNET_ID}" \
      || echo "[WARN] Subnet not found: ${SUBNET_ID}"
  fi
done

# ─────────────────────────────────────────────
# Step 9 — VPC
# All resources inside must be deleted first or this will fail.
# ─────────────────────────────────────────────
if [ -n "${VPC_ID}" ]; then
  echo "[INFO] Deleting VPC: ${VPC_ID}..."
  aws ec2 delete-vpc \
    --vpc-id "${VPC_ID}" \
    --region "${AWS_REGION}" 2>/dev/null \
    && echo "[OK] VPC deleted" \
    || echo "[WARN] VPC not found or still has dependencies"
fi

echo ""
echo "[OK] Cleanup complete."