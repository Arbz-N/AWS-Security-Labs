#!/usr/bin
# 04-generate-credential-report.sh
# Generates the IAM credential report and extracts the mfa_active column
# for every user in the account.
#
# The credential report is a CSV that includes: password age, access key ages,
# last-used dates, and MFA status for every IAM user.
#
# Usage: bash 04-generate-credential-report.sh

set -euo pipefail

echo "[INFO] Requesting credential report generation..."

# The report takes a few seconds to generate. The generate command returns
# the current state: IN_PROGRESS, STARTED, or COMPLETE.
aws iam generate-credential-report > /dev/null

# Poll until the report reaches COMPLETE state.
STATUS="IN_PROGRESS"
while [ "${STATUS}" != "COMPLETE" ]; do
  STATUS=$(aws iam generate-credential-report \
    --query 'State' \
    --output text 2>/dev/null || echo "IN_PROGRESS")
  echo "[INFO] Report status: ${STATUS}..."
  if [ "${STATUS}" != "COMPLETE" ]; then
    sleep 3
  fi
done

echo "[OK] Credential report ready."
echo ""
echo "[INFO] Extracting user and mfa_active columns..."
echo ""

# The report content is base64-encoded. Decode it and extract columns 1 (user)
# and 8 (mfa_active) from the CSV using cut.
# Column numbers: 1=user, 2=arn, 3=user_creation_time, 4=password_enabled,
# 5=password_last_used, 6=password_last_changed, 7=password_next_rotation,
# 8=mfa_active
aws iam get-credential-report \
  --query 'Content' \
  --output text | base64 -d | \
  awk -F',' 'NR==1{print "USER,MFA_ACTIVE"} NR>1{print $1","$8}'

echo ""
echo "[INFO] mfa_active=true  means MFA is enabled  [OK]"
echo "[INFO] mfa_active=false means MFA is missing  [FAIL]"
echo ""
echo "[INFO] Full report (all columns):"
aws iam get-credential-report \
  --query 'Content' \
  --output text | base64 -d | \
  cut -d',' -f1,4,5,8,9,10
# Fields: user, password_enabled, password_last_used, mfa_active,
#         access_key_1_active, access_key_2_active