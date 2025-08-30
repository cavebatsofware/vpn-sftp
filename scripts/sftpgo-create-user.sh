#!/usr/bin/env bash
set -euo pipefail

# Create an SFTPGo user on the local filesystem via the SFTPGo REST API.
#
# What this does
# - Reads connection config from terraform outputs (IP, region)
# - Fetches the SFTPGo admin password from AWS SSM Parameter Store
# - Logs into SFTPGo to obtain a JWT
# - Creates a user with a local (S3 backed) filesystem home at /data/{username} (this is because the container s3 is mounted under /data)
#
# Requirements
# - AWS CLI configured with permissions for SSM:GetParameter (with decryption)
# - curl and jq installed locally
# - SFTPGo admin API available on the server (port 8080, accessible from your host/VPN)
usage() {
  cat <<USAGE
Usage: $0 [-e env] [-u username] [-p password] [-O otp] [-h]
If flags are omitted, you'll be prompted interactively.
USAGE
}

# Inputs from env/flags
ENVIRONMENT="${ENVIRONMENT:-}"
USERNAME="${USERNAME:-}"
PASSWORD="${PASSWORD:-}"
OTP="${OTP:-}"

while getopts ":e:u:p:O:h" opt; do
  case $opt in
    e) ENVIRONMENT="$OPTARG";;
    u) USERNAME="$OPTARG";;
    p) PASSWORD="$OPTARG";;
    O) OTP="$OPTARG";;
    h) usage; exit 0;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage; exit 2;;
    \?) echo "Unknown option -$OPTARG" >&2; usage; exit 2;;
  esac
done

if [[ -z "$ENVIRONMENT" ]]; then read -rp "Environment (dev|staging|prod): " ENVIRONMENT; fi
if [[ -z "$USERNAME" ]]; then read -rp "SFTP username: " USERNAME; fi
if [[ -z "$PASSWORD" ]]; then read -rp "Password (leave empty to auto-generate): " PASSWORD; fi

TF_OUT() { terraform output -raw "$1" 2>/dev/null || true; }

SFTP_IP=${SFTP_IP:-$(TF_OUT sftp_private_ip)}
AWS_REGION=${AWS_REGION:-$(TF_OUT region)}
ADMIN_SSM_PATH=${ADMIN_SSM_PATH:-"/$(TF_OUT project_name || echo $PROJECT_NAME)/${ENVIRONMENT}/sftpgo/admin-password"}

if [[ -z "${SFTP_IP}" || -z "${AWS_REGION}" ]]; then
  echo "Missing SFTP_IP/AWS_REGION. Ensure terraform outputs are available or set env vars." >&2
  exit 1
fi

if [[ -z "${PASSWORD}" ]]; then
  # Generate a reasonably strong default password if none provided
  PASSWORD=$(openssl rand -base64 18 | tr -d '\n')
fi

# Retrieve SFTPGo admin password from SSM so we can authenticate against the API
echo "Fetching SFTPGo admin password from SSM: ${ADMIN_SSM_PATH}"
ADMIN_PASSWORD=$(aws ssm get-parameter --with-decryption \
  --name "${ADMIN_SSM_PATH}" --query 'Parameter.Value' --output text \
  --region "${AWS_REGION}" 2>/dev/null || true)

if [[ -z "${ADMIN_PASSWORD}" ]]; then
  echo "Admin password not found in SSM; set ${ADMIN_SSM_PATH}." >&2
  exit 1
fi

BASE_URL="http://${SFTP_IP}:8080"

# Preflight: confirm API is reachable and report version (helps debug)
VERSION_RESP=$(curl -sS -H 'Accept: application/json' "${BASE_URL}/api/v2/version" || true)
if jq -e '.version' >/dev/null 2>&1 <<<"$VERSION_RESP"; then
  echo "SFTPGo API reachable. Version: $(jq -r .version <<<"$VERSION_RESP")"
else
  echo "WARNING: Could not read SFTPGo version from ${BASE_URL}/api/v2/version" >&2
fi

# Authenticate to obtain a JWT token for subsequent API calls
echo "Logging in to SFTPGo admin at ${BASE_URL}"

basic_token() {
  local endpoint="$1"
  local auth
  auth=$(printf '%s:%s' "admin" "${ADMIN_PASSWORD}" | base64 | tr -d '\n')
  local -a args=( -sS -w '\n%{http_code}' -X GET "${BASE_URL}${endpoint}" -H 'Accept: application/json' -H "Authorization: Basic ${auth}" )
  if [[ -n "${OTP}" ]]; then
    args+=( -H "X-SFTPGO-OTP: ${OTP}" )
  fi
  local resp code body
  resp=$(curl "${args[@]}")
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  echo "$code" > /tmp/sftpgo_login_code
  echo "$body" > /tmp/sftpgo_login_body
  jq -r '.access_token // empty' <<<"$body"
}

# Try token endpoints with Basic auth
TOKEN=$(basic_token "/api/v2/token")
if [[ -z "${TOKEN}" ]]; then
  TOKEN=$(basic_token "/api/v2/admins/token")
fi

if [[ -z "${TOKEN}" || "${TOKEN}" == "null" ]]; then
  echo "Failed to obtain admin token with Basic auth." >&2
  echo "HTTP $(cat /tmp/sftpgo_login_code 2>/dev/null || echo '?'):" >&2
  cat /tmp/sftpgo_login_body >&2 || true
  echo >&2
  # Retry with manual password and optional OTP if needed
  read -rsp "Enter admin password to retry (input hidden): " ADMIN_PASSWORD_MANUAL; echo
  read -rp "Enter OTP if enabled (or leave blank): " OTP_MANUAL
  if [[ -n "$ADMIN_PASSWORD_MANUAL" ]]; then
    ADMIN_PASSWORD="$ADMIN_PASSWORD_MANUAL"
  fi
  if [[ -n "$OTP_MANUAL" ]]; then
    OTP="$OTP_MANUAL"
  fi
  TOKEN=$(basic_token "/api/v2/token")
  if [[ -z "${TOKEN}" ]]; then
    TOKEN=$(basic_token "/api/v2/admins/token")
  fi
fi

if [[ -z "${TOKEN}" || "${TOKEN}" == "null" ]]; then
  echo "Still failed to obtain admin token. Verify credentials, OTP, and API path." >&2
  exit 1
fi

# Build and send the user creation request with local filesystem
echo "Creating user '${USERNAME}' with home '/data/${USERNAME}'"
PAYLOAD=$(jq -n \
  --arg u "$USERNAME" \
  --arg p "$PASSWORD" \
  --arg r "$AWS_REGION" \
  '{
    username: $u,
    status: 1,
    password: $p,
    home_dir: ("/data/" + $u),
    permissions: { "/": ["*"] },
    filesystem: {
      provider: 0
    }
  }')

RESP=$(curl -sS -X POST "${BASE_URL}/api/v2/users" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "${PAYLOAD}")

if echo "$RESP" | jq -e '.id' >/dev/null 2>&1; then
  echo "User created: ${USERNAME}"
  echo "Password: ${PASSWORD}"
else
  echo "Create user response:" >&2
  echo "$RESP" | jq . >&2 || echo "$RESP" >&2
  exit 1
fi
