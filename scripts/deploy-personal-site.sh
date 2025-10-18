#!/bin/bash

set -e

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <stack_ip> [ssh_key_path]"
    echo "  stack_ip: IP address of the VPN server instance"
    echo "  ssh_key_path: Path to SSH private key (optional, defaults to ~/.ssh/id_rsa)"
    exit 1
fi

STACK_IP="$1"
SSH_KEY="${2:-$HOME/.ssh/id_rsa}"

if [[ ! -f "$SSH_KEY" ]]; then
    echo "Error: SSH key not found at $SSH_KEY"
    exit 1
fi

echo "Adding SSH key to agent (you may be prompted for your key password)..."
ssh-add "$SSH_KEY"

echo "Getting ECR registry URL from Terraform..."
ECR_REGISTRY=$(terraform output -raw personal_site_ecr_repository_url | cut -d'/' -f1)

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Copying database initialization script to instance..."
scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/init-personal-site-db.sh" ec2-user@"$STACK_IP":/tmp/init-personal-site-db.sh

echo "Deploying personal-site container to $STACK_IP..."

ssh -o StrictHostKeyChecking=no ec2-user@"$STACK_IP" << EOF
set -e

echo "Navigating to docker-compose directory..."
cd /opt/docker-app

echo "Current running containers:"
docker compose ps

echo "Authenticating with ECR..."
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin $ECR_REGISTRY

echo "Pulling latest personal-site image..."
docker compose pull personal-site

echo "Ensuring postgres service is running..."
docker compose up -d postgres

echo "Waiting for postgres to be healthy..."
for i in {1..30}; do
    if docker compose exec -T postgres pg_isready -U personal_site_user -d personal_site > /dev/null 2>&1; then
        echo "✅ PostgreSQL is ready"
        break
    fi
    echo "Waiting for PostgreSQL... (attempt \$i/30)"
    sleep 2
done

# Check if database needs initialization (check for uuid-ossp extension)
echo "Checking if database needs initialization..."
DB_INITIALIZED=\$(docker compose exec -T postgres psql -U personal_site_user -d personal_site -tAc "SELECT COUNT(*) FROM pg_extension WHERE extname='uuid-ossp';" 2>/dev/null || echo "0")

if [ "\$DB_INITIALIZED" = "0" ]; then
    echo "📦 Database not initialized. Running initialization script..."

    # Copy init script into the postgres container
    docker cp /tmp/init-personal-site-db.sh personal-site-db:/tmp/init-db.sh

    # Run the initialization script inside postgres container
    docker compose exec -T postgres bash -c "
        export POSTGRES_USER=personal_site_user
        export POSTGRES_DB=personal_site
        chmod +x /tmp/init-db.sh
        /tmp/init-db.sh
    "

    echo "✅ Database initialization complete"
else
    echo "✅ Database already initialized, skipping initialization"
fi

echo "Stopping and removing old personal-site container..."
docker compose stop personal-site
docker compose rm -f personal-site

echo "Starting updated personal-site container (migrations will run automatically)..."
docker compose up -d personal-site

# This usually takes a bit of time for the container to be fully healthy
echo "Waiting for container to be healthy, sleeping for 30s..."
sleep 30

echo "Checking personal-site container status:"
docker compose ps personal-site
docker compose logs --tail=20 personal-site

if docker compose exec personal-site curl -f http://localhost:3000/health > /dev/null 2>&1; then
    echo "🔄 Retrying health check, sleeping for 1s..."
    sleep 1
    if docker compose exec personal-site curl -f http://localhost:3000/health > /dev/null 2>&1; then
        echo "✅ personal-site container is healthy and responding"
    else
        echo "❌ personal-site container health check failed on second attempt"
        exit 1
    fi
else
    echo "❌ personal-site container health check failed"
    exit 1
fi

echo "✅ Deployment completed successfully!"
EOF

echo "✅ Personal site deployment finished!"