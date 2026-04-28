#!/usr/bin/env bash
# 01-check-mfa-status.sh
# Lists all IAM users and checks which ones have MFA devices registered.
#
# Usage: bash 01-check-mfa-status.sh

set -euo pipefail

echo "[INFO] Listing all IAM users..."
aws iam list-users \
  --query 'Users[].[UserName,UserId,PasswordLastUsed]' \
  --output table

echo ""
echo "[INFO] Checking MFA device status per user..."
echo ""

# Retrieve the list of all usernames as a plain text list.
USERS=$(aws iam list-users \
  --query 'Users[].UserName' \
  --output text)

# Iterate over each username and check for registered MFA devices.
# An empty response from list-mfa-devices means MFA is not configured.
for USER in $USERS; do
  MFA_DEVICES=$(aws iam list-mfa-devices \
    --user-name "${USER}" \
    --query 'MFADevices[].SerialNumber' \
    --output text 2>/dev/null || true)

  if [ -z "${MFA_DEVICES}" ]; then
    echo "[FAIL] ${USER} — MFA not enabled"
  else
    echo "[OK]   ${USER} — MFA device: ${MFA_DEVICES}"
  fi
done

echo ""
echo "[INFO] Done. Users marked [FAIL] need MFA configured before ForceMFAPolicy is attached."