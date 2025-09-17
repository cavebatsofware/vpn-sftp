#!/bin/bash

# Script to update AMI ID in terraform.tfvars with the latest Amazon Linux 2023 ARM64 AMI
# Usage: ./scripts/update-ami.sh [environment]
# Example: ./scripts/update-ami.sh prod

set -euo pipefail

ENVIRONMENT=${1:-prod}
TFVARS_FILE="environments/${ENVIRONMENT}/terraform.tfvars"
REGION="us-east-2"

# Check if tfvars file exists
if [[ ! -f "$TFVARS_FILE" ]]; then
    echo "Error: $TFVARS_FILE not found"
    exit 1
fi

echo "Fetching latest Amazon Linux 2023 ARM64 AMI for region $REGION..."

# Get the latest AMI ID
LATEST_AMI=$(aws ec2 describe-images \
    --owners 137112412989 \
    --filters \
        "Name=name,Values=al2023-ami-*-arm64" \
        "Name=architecture,Values=arm64" \
        "Name=virtualization-type,Values=hvm" \
        "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text \
    --region "$REGION")

if [[ -z "$LATEST_AMI" || "$LATEST_AMI" == "None" ]]; then
    echo "Error: Could not fetch latest AMI ID"
    exit 1
fi

# Get current AMI from tfvars
CURRENT_AMI=$(grep "arm64_ami_id_override" "$TFVARS_FILE" | cut -d'"' -f2)

echo "Current AMI: $CURRENT_AMI"
echo "Latest AMI:  $LATEST_AMI"

if [[ "$CURRENT_AMI" == "$LATEST_AMI" ]]; then
    echo "✅ AMI is already up to date"
    exit 0
fi

# Update the tfvars file
echo "Updating $TFVARS_FILE..."
sed -i.bak "s/arm64_ami_id_override = \"$CURRENT_AMI\"/arm64_ami_id_override = \"$LATEST_AMI\"/" "$TFVARS_FILE"

echo "✅ Updated AMI ID from $CURRENT_AMI to $LATEST_AMI"
echo "📝 Backup saved as ${TFVARS_FILE}.bak"

# Show the AMI details
echo ""
echo "AMI Details:"
aws ec2 describe-images \
    --image-ids "$LATEST_AMI" \
    --query 'Images[0].[Name,CreationDate,Description]' \
    --output table \
    --region "$REGION"

echo ""
echo "🔄 Run 'terraform plan' to see what will change"