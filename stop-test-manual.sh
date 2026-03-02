#!/bin/bash

# Manual container stop script for authserver TEST environment
# This script stops and cleans up all test containers

set -e  # Exit on any error

echo "🛑 Stopping authserver TEST containers..."

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
echo -e "${YELLOW}Stopping test services...${NC}"
podman-compose -f podman-compose.yml --project-name opt down || true

# Remove containers
echo -e "${YELLOW}Removing test containers...${NC}"
podman stop $(podman ps -aq --filter "label=com.docker.compose.project=opt") 2>/dev/null || true
podman rm $(podman ps -aq --filter "label=com.docker.compose.project=opt") 2>/dev/null || true

# Remove volumes (optional - comment out if you want to keep data)
echo -e "${YELLOW}Removing test volumes...${NC}"
podman volume rm postgres_test_data 2>/dev/null || true

# Remove network (force if necessary)
echo -e "${YELLOW}Removing test network...${NC}"
podman network rm aztech-test-network 2>/dev/null || echo -e "${BLUE}Network aztech-test-network not found or still in use${NC}"

# Remove images (optional - comment out if you want to keep built images)
echo -e "${YELLOW}Removing test images...${NC}"
podman rmi localhost/opt_authserver-test-backend:latest 2>/dev/null || true
podman rmi localhost/opt_authserver-test-frontend:latest 2>/dev/null || true
podman rmi localhost/opt_authserver-test-db:latest 2>/dev/null || true

echo -e "${GREEN}Test cleanup complete${NC}"