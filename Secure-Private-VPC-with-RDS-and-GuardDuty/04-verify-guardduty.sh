#!/usr/bin/env bash
# 04-verify-guardduty.sh
# Generates sample GuardDuty findings and lists current findings.
# Used to confirm the detector is operational before real threats occur.
#
# Prerequisites:
#   DETECTOR_ID must be exported from 02-enable-guardduty.sh
#   AWS_REGION must be exported
# Usage: bash 04-verify-guardduty.sh

set -euo pipefail

# ============================================================
# CONFIG
# ============================================================
AWS_REGION="${AWS_REGION:-your-region}"
DETECTOR_ID="${DETECTOR_ID:-}"
# ============================================================

# If DETECTOR_ID was not exported, look it up automatically.
if [ -z "${DETECTOR_ID}" ]; then
  echo "[INFO] DETECTOR_ID not set — looking up existing detector..."
  DETECTOR_ID=$(aws guardduty list-detectors \
    --region "${AWS_REGION}" \
    --query 'DetectorIds[0]' \
    --output text)
  echo "[OK] Found detector: ${DETECTOR_ID}"
fi

echo "[INFO] Generating sample findings..."

# Sample findings simulate real threat types without actual malicious activity.
# They are clearly labelled as SAMPLE in the console and do not trigger alerts
# in production notification pipelines unless specifically configured to do so.
aws guardduty create-sample-findings \
  --detector-id "${DETECTOR_ID}" \
  --finding-types \
    "Recon:EC2/PortProbeUnprotectedPort" \
    "UnauthorizedAccess:EC2/SSHBruteForce" \
  --region "${AWS_REGION}"

echo "[OK] Sample findings generated"
echo "[INFO] Waiting 10 seconds for findings to propagate..."
sleep 10

# ─────────────────────────────────────────────
# List all finding IDs
# ─────────────────────────────────────────────
echo "[INFO] Listing all finding IDs..."
aws guardduty list-findings \
  --detector-id "${DETECTOR_ID}" \
  --region "${AWS_REGION}" \
  --query 'FindingIds' \
  --output table

# ─────────────────────────────────────────────
# Get details of the first 3 findings
# ─────────────────────────────────────────────
echo "[INFO] Retrieving details for the first 3 findings..."

FINDING_IDS=$(aws guardduty list-findings \
  --detector-id "${DETECTOR_ID}" \
  --region "${AWS_REGION}" \
  --query 'FindingIds[0:3]' \
  --output json)

# The finding IDs are returned as a JSON array.
# tr removes brackets and quotes, converting to a space-separated string
# that the get-findings command accepts as individual arguments.
aws guardduty get-findings \
  --detector-id "${DETECTOR_ID}" \
  --finding-ids $(echo "${FINDING_IDS}" | tr -d '[]"' | tr ',' ' ') \
  --query 'Findings[*].{Type:Type,Severity:Severity,Title:Title}' \
  --output table \
  --region "${AWS_REGION}"

echo ""
echo "[OK] GuardDuty verification complete."
echo "[INFO] View findings in: AWS Console -> GuardDuty -> Findings"