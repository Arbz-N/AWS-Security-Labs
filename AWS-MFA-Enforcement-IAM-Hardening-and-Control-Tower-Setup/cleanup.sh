#!/bin/bash
# cleanup.sh
# Removes the MFA device, virtual MFA device, policy attachment, and policy.
#
# Prerequisites: AWS CLI configured with admin credentials
# Usage        : bash cleanup.sh

set -euo pipefail

# ============================================================
# CONFIG
# ============================================================
TARGET_USER="your-iam-username"   # Same user used in 02-create-mfa-policy.sh
POLICY_NAME="ForceMFAPolicy"
# ============================================================

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

echo "[INFO] Starting cleanup for user: ${TARGET_USER}"

# ─────────────────────────────────────────────
# Step 1 — Deactivate the MFA device on the user
# The device must be deactivated before it can be deleted.
# ─────────────────────────────────────────────
SERIAL=$(aws iam list-mfa-devices \
  --user-name "${TARGET_USER}" \
  --query 'MFADevices[0].SerialNumber' \
  --output text 2>/dev/null || true)

if [ -n "${SERIAL}" ] && [ "${SERIAL}" != "None" ]; then
  echo "[INFO] Deactivating MFA device: ${SERIAL}..."
  aws iam deactivate-mfa-device \
    --user-name "${TARGET_USER}" \
    --serial-number "${SERIAL}"
  echo "[OK] MFA device deactivated"

  # Delete the virtual MFA device itself (not just the association).
  # This step only applies to virtual (software) MFA devices.
  # Hardware tokens cannot be deleted this way — remove them from the user only.
  if echo "${SERIAL}" | grep -q "arn:aws:iam"; then
    echo "[INFO] Deleting virtual MFA device: ${SERIAL}..."
    aws iam delete-virtual-mfa-device \
      --serial-number "${SERIAL}"
    echo "[OK] Virtual MFA device deleted"
  fi
else
  echo "[WARN] No MFA device found for ${TARGET_USER} — skipping deactivation"
fi

# ─────────────────────────────────────────────
# Step 2 — Detach ForceMFAPolicy from the user
# Must detach before the policy can be deleted.
# ─────────────────────────────────────────────
echo "[INFO] Detaching ${POLICY_NAME} from user: ${TARGET_USER}..."
aws iam detach-user-policy \
  --user-name "${TARGET_USER}" \
  --policy-arn "${POLICY_ARN}" 2>/dev/null \
  && echo "[OK] Policy detached" \
  || echo "[WARN] Policy was not attached to this user — skipping"

# ─────────────────────────────────────────────
# Step 3 — Delete the ForceMFAPolicy
# A policy cannot be deleted if it is still attached to any user, group, or role.
# ─────────────────────────────────────────────
echo "[INFO] Deleting policy: ${POLICY_ARN}..."
aws iam delete-policy \
  --policy-arn "${POLICY_ARN}" 2>/dev/null \
  && echo "[OK] Policy deleted" \
  || echo "[WARN] Policy not found — may already be deleted"

echo ""
echo "[OK] CLI cleanup complete."
echo ""
echo "[INFO] Manual steps required in the AWS Console:"
echo ""
echo "  Root Account MFA (optional — strongly recommended to keep):"
echo "    Security Credentials -> MFA -> Remove device"
echo ""
echo "  Control Tower Landing Zone (if applicable):"
echo "    1. Unenroll all accounts created via Account Factory"
echo "    2. Close or unenroll the Log Archive and Audit accounts"
echo "    3. Control Tower -> Landing zone settings -> Delete landing zone"
echo "    4. Close sub-accounts separately via AWS Organizations if needed"
echo ""
echo "[WARN] Root account MFA removal is irreversible until re-setup."
echo "[WARN] Keep root MFA enabled on real accounts — remove only for lab cleanup."