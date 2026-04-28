#!/usr/bin/env bash
# 03-set-password-policy.sh
# Applies a strong account-wide IAM password policy.
# This policy applies to all IAM users in the account.
#
# Usage: bash 03-set-password-policy.sh

set -euo pipefail

echo "[INFO] Applying account-wide IAM password policy..."

aws iam update-account-password-policy \
  --minimum-password-length 14 \
  --require-symbols \
  --require-numbers \
  --require-uppercase-characters \
  --require-lowercase-characters \
  --allow-users-to-change-password \
  --max-password-age 90 \
  --password-reuse-prevention 12 \
  --hard-expiry false
# --minimum-password-length 14   : Minimum 14 characters reduces brute-force risk
# --require-symbols               : Forces inclusion of special characters (!@#$ etc.)
# --require-numbers               : At least one numeric digit
# --require-uppercase-characters  : At least one A-Z character
# --require-lowercase-characters  : At least one a-z character
# --allow-users-to-change-password: Users can rotate their own passwords
# --max-password-age 90           : Passwords expire after 90 days
# --password-reuse-prevention 12  : Cannot reuse any of the last 12 passwords
# --hard-expiry false             : Expired-password users can still log in to change it
#                                   (hard-expiry true = locked out until admin resets)

echo "[OK] Password policy applied."
echo ""
echo "[INFO] Verifying applied policy..."
aws iam get-account-password-policy --output table