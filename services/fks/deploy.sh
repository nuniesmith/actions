#!/bin/bash
# FKS Trading Systems Deployment Script

set -euo pipefail

SERVICE_NAME="fks"
SERVICE_USER="fks_user"
SERVICE_DIR="/home/$SERVICE_USER/$SERVICE_NAME"
REPO_URL="https://github.com/$GITHUB_REPOSITORY_OWNER/$SERVICE_NAME.git"

echo "🚢 Deploying FKS Trading Systems..."

# Ensure service user exists
if ! id "$SERVICE_USER" &>/dev/null; then
    echo "❌ Service user $SERVICE_USER does not exist"
    exit 1
fi

# Clone or update repository
if [[ -d "$SERVICE_DIR" ]]; then
    echo "📥 Updating existing repository..."
    cd "$SERVICE_DIR"
    sudo -u "$SERVICE_USER" git pull origin main
else
    echo "📥 Cloning repository..."
    sudo -u "$SERVICE_USER" git clone "$REPO_URL" "$SERVICE_DIR"
fi

cd "$SERVICE_DIR"

# Ensure proper ownership
chown -R "$SERVICE_USER:$SERVICE_USER" "$SERVICE_DIR"

# Setup environment variables
if [[ -f ".env.template" ]]; then
    echo "⚙️ Setting up environment variables..."
    sudo -u "$SERVICE_USER" cp .env.template .env
    
    # Replace placeholders with actual values
    if [[ -n "${DOCKER_USERNAME:-}" ]]; then
        sudo -u "$SERVICE_USER" sed -i "s/DOCKER_USERNAME_PLACEHOLDER/$DOCKER_USERNAME/g" .env
    fi
    
    if [[ -n "${DOCKER_TOKEN:-}" ]]; then
        sudo -u "$SERVICE_USER" sed -i "s/DOCKER_TOKEN_PLACEHOLDER/$DOCKER_TOKEN/g" .env
    fi
    
    if [[ -n "${JWT_SECRET:-}" ]]; then
        sudo -u "$SERVICE_USER" sed -i "s/JWT_SECRET_PLACEHOLDER/$JWT_SECRET/g" .env
    fi
fi

# Docker login if credentials provided
if [[ -n "${DOCKER_USERNAME:-}" && -n "${DOCKER_TOKEN:-}" ]]; then
    echo "🐳 Logging into Docker Hub..."
    echo "$DOCKER_TOKEN" | sudo -u "$SERVICE_USER" docker login --username "$DOCKER_USERNAME" --password-stdin
fi

# Start services
if [[ -f "docker-compose.yml" ]]; then
    echo "🚀 Starting Docker services..."
    sudo -u "$SERVICE_USER" docker-compose down --remove-orphans || true
    sudo -u "$SERVICE_USER" docker-compose pull
    sudo -u "$SERVICE_USER" docker-compose up -d
elif [[ -f "start.sh" ]]; then
    echo "🚀 Running start script..."
    sudo -u "$SERVICE_USER" chmod +x start.sh
    sudo -u "$SERVICE_USER" ./start.sh
else
    echo "❌ No deployment method found (docker-compose.yml or start.sh)"
    exit 1
fi

# Health check
echo "🏥 Performing health check..."
sleep 10

if sudo -u "$SERVICE_USER" docker-compose ps | grep -q "Up"; then
    echo "✅ FKS services are running"
else
    echo "⚠️ Some services may not be running properly"
    sudo -u "$SERVICE_USER" docker-compose ps
fi

echo "✅ FKS deployment complete!"
echo "🌐 Service should be available at: https://fks.7gram.xyz"
