#!/usr/bin
# 02-create-mfa-policy.sh
# Creates the ForceMFAPolicy and attaches it to the specified IAM user.
# The policy denies all AWS actions unless the session includes a valid MFA token.
#
# Prerequisites:
#   mfa-enforce-policy.json must be in the same directory as this script.
#   The target user must already have MFA configured before this policy is attached.
#   Attaching the policy to a user who has no MFA set up will lock them out.
#
# Usage: bash 02-create-mfa-policy.sh

set -euo pipefail

# ============================================================
# CONFIG
# ============================================================
TARGET_USER="your-iam-username"     # IAM username to attach the policy to
POLICY_NAME="ForceMFAPolicy"
POLICY_FILE="mfa-enforce-policy.json"
# ============================================================

# Resolve the account ID dynamically so no real account ID appears in config.
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

echo "[INFO] Account ID: ${ACCOUNT_ID}"
echo "[INFO] Creating IAM policy: ${POLICY_NAME}..."

# Create the policy from the JSON document.
# If the policy already exists this command will fail — check with list-policies first.
aws iam create-policy \
  --policy-name "${POLICY_NAME}" \
  --policy-document "file://${POLICY_FILE}" \
  --description "Deny all AWS actions when MFA is not present in the session"

echo "[OK] Policy created: ${POLICY_ARN}"

# Confirm the target user has MFA before attaching the policy.
# Attaching to a user without MFA results in an account lockout for that user.
MFA_CHECK=$(aws iam list-mfa-devices \
  --user-name "${TARGET_USER}" \
  --query 'MFADevices[].SerialNumber' \
  --output text 2>/dev/null || true)

if [ -z "${MFA_CHECK}" ]; then
  echo "[WARN] User '${TARGET_USER}' does not have an MFA device registered."
  echo "[WARN] Attaching ForceMFAPolicy now will lock them out of all AWS actions."
  echo "[WARN] Have the user set up MFA first, then re-run this script."
  exit 1
fi

echo "[OK] MFA device found for ${TARGET_USER}: ${MFA_CHECK}"
echo "[INFO] Attaching ${POLICY_NAME} to user: ${TARGET_USER}..."

aws iam attach-user-policy \
  --user-name "${TARGET_USER}" \
  --policy-arn "${POLICY_ARN}"

echo "[OK] Policy attached. ${TARGET_USER} now requires MFA for all actions."
echo ""
echo "[INFO] To attach to additional users, run:"
echo "  aws iam attach-user-policy --user-name OTHER_USER --policy-arn ${POLICY_ARN}"
echo ""
echo "[INFO] To attach to a group (recommended for scale):"
echo "  aws iam attach-group-policy --group-name YOUR_GROUP --policy-arn ${POLICY_ARN}"