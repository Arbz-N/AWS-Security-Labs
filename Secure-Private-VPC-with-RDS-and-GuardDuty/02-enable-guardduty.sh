#!/bin/bash
# 02-enable-guardduty.sh
# Enables GuardDuty and activates the RDS and S3 protection plans.
#
# Prerequisites: AWS_REGION must be exported before running.
# Usage        : bash 02-enable-guardduty.sh

set -euo pipefail

# ============================================================
# CONFIG
# ============================================================
AWS_REGION="${AWS_REGION:-your-region}"
# ============================================================

echo "[INFO] Enabling GuardDuty in region: ${AWS_REGION}"

# Create a GuardDuty detector. A detector is the regional GuardDuty resource
# that receives findings. One detector per region per account is the limit.
# The --enable flag activates it immediately on creation.
DETECTOR_ID=$(aws guardduty create-detector \
  --enable \
  --region "${AWS_REGION}" \
  --query 'DetectorId' \
  --output text)

echo "[OK] GuardDuty Detector ID: ${DETECTOR_ID}"

# Verify the detector is active before enabling protection plans.
aws guardduty get-detector \
  --detector-id "${DETECTOR_ID}" \
  --region "${AWS_REGION}" \
  --query '{Status:Status,FindingFrequency:FindingPublishingFrequency}' \
  --output table

# ─────────────────────────────────────────────
# Protection Plans
# ─────────────────────────────────────────────

# RDS Protection monitors RDS authentication events.
# Without this, GuardDuty does not see login attempts to RDS databases.
# It detects findings in the CredentialAccess:RDS/* and Anomaly:RDS/* categories.
aws guardduty update-detector \
  --detector-id "${DETECTOR_ID}" \
  --region "${AWS_REGION}" \
  --features '[
    {
      "Name": "RDS_LOGIN_EVENTS",
      "Status": "ENABLED"
    }
  ]'
echo "[OK] RDS protection plan enabled"

# S3 Protection extends GuardDuty to monitor S3 data access events.
# Without this, GuardDuty only sees S3 management events (bucket creation, etc.)
# not data events (GetObject, PutObject, DeleteObject).
aws guardduty update-detector \
  --detector-id "${DETECTOR_ID}" \
  --region "${AWS_REGION}" \
  --features '[
    {
      "Name": "S3_DATA_EVENTS",
      "Status": "ENABLED"
    }
  ]'
echo "[OK] S3 protection plan enabled"

echo ""
echo "[INFO] Export this variable before running cleanup.sh:"
echo ""
echo "  export DETECTOR_ID=${DETECTOR_ID}"
echo ""
echo "[OK] GuardDuty setup complete."