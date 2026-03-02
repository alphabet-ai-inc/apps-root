#!/bin/bash

# Manual container stop script for authserver
# This script stops and cleans up all containers

set -e  # Exit on any error

echo "🛑 Stopping authserver containers..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
if ! command_exists podman-compose; then
    echo -e "${RED}Error: podman-compose is not installed${NC}"
    exit 1
fi

# Stop services
echo -e "${YELLOW}Stopping services...${NC}"
podman-compose -f podman-compose.yml --project-name srv down || true

# Remove containers
echo -e "${YELLOW}Removing containers...${NC}"
podman stop $(podman ps -aq --filter "label=com.docker.compose.project=srv") 2>/dev/null || true
podman rm $(podman ps -aq --filter "label=com.docker.compose.project=srv") 2>/dev/null || true

# Remove volumes (optional - comment out if you want to keep data)
echo -e "${YELLOW}Removing volumes...${NC}"
podman volume rm srv_postgres_data 2>/dev/null || true

# Remove network (force if necessary)
echo -e "${YELLOW}Removing network...${NC}"
podman network rm srv_aztech-network 2>/dev/null || echo -e "${BLUE}Network srv_aztech-network not found or still in use${NC}"

# Remove images (optional - comment out if you want to keep built images)
echo -e "${YELLOW}Removing images...${NC}"
podman rmi localhost/srv_authserver-backend:latest 2>/dev/null || true
podman rmi localhost/srv_authserver-frontend:latest 2>/dev/null || true
podman rmi localhost/srv_authserver-db:latest 2>/dev/null || true

echo -e "${GREEN}Cleanup complete!${NC}"

# Show remaining containers
echo -e "${BLUE}Remaining containers:${NC}"
podman ps -a