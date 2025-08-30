#!/usr/bin/env bash
set -euo pipefail

# Seed s3fs passwd content from your local AWS credentials, or store it in SSM.
#
# Usage examples:
#   ./scripts/seed-s3fs-passwd.sh -p default            # print ACCESS_KEY:SECRET[:SESSION]
#   ./scripts/seed-s3fs-passwd.sh -p meeseeks -o ssm -n \
#     "/vpn-server/dev/s3fs/passwd" -r us-east-1        # write SecureString to SSM
#
# Then set one of:
#   - TF_VAR_s3fs_passwd to the printed value
#   - or var.s3fs_ssm_parameter_name to the SSM path you used

PROFILE="default"
OUTPUT="print"   # print | ssm
PARAM_NAME=""
REGION=""

while getopts ":p:o:n:r:h" opt; do
  case $opt in
    p) PROFILE="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    n) PARAM_NAME="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    h)
      echo "Usage: $0 [-p profile] [-o print|ssm] [-n ssm-param-name] [-r region]"; exit 0 ;;
    *) echo "Invalid option: -$OPTARG" >&2; exit 2 ;;
  esac
done

# Pull creds via AWS CLI (supports shared config/credentials resolution)
AKI=$(aws configure get aws_access_key_id --profile "$PROFILE" || true)
SAK=$(aws configure get aws_secret_access_key --profile "$PROFILE" || true)
STK=$(aws configure get aws_session_token --profile "$PROFILE" || true)

if [[ -z "$AKI" || -z "$SAK" ]]; then
  echo "Missing credentials for profile '$PROFILE'" >&2
  exit 1
fi

CONTENT="$AKI:$SAK"
if [[ -n "$STK" ]]; then
  CONTENT="$CONTENT:$STK"
fi

case "$OUTPUT" in
  print)
    echo "$CONTENT"
    ;;
  ssm)
    if [[ -z "$PARAM_NAME" || -z "$REGION" ]]; then
      echo "When -o ssm, both -n <param-name> and -r <region> are required" >&2
      exit 2
    fi
    aws ssm put-parameter \
      --name "$PARAM_NAME" \
      --type SecureString \
      --value "$CONTENT" \
      --overwrite \
      --region "$REGION"
    echo "Wrote SecureString to SSM: $PARAM_NAME (region $REGION)"
    ;;
  *)
    echo "Unknown output mode: $OUTPUT (use print|ssm)" >&2
    exit 2
    ;;
esac
