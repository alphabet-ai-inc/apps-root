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
echo -e "${YELLOW}Stopping services...${NC}"
podman-compose -f podman-compose.yml --project-name opt down || true

# Remove containers by name pattern (more reliable than labels)
echo -e "${YELLOW}Removing containers...${NC}"
podman stop $(podman ps -aq --filter name=opt_) 2>/dev/null || true
podman rm $(podman ps -aq --filter name=opt_) 2>/dev/null || true

# Remove volumes (optional - comment out if you want to keep data)
echo -e "${YELLOW}Removing volumes...${NC}"
podman volume rm postgres_test_data 2>/dev/null || true

# Remove images (optional - comment out if you want to keep built images)
echo -e "${YELLOW}Removing images...${NC}"
podman rmi localhost/opt_authserver-backend:latest 2>/dev/null || true
podman rmi localhost/opt_authserver-frontend:latest 2>/dev/null || true

echo -e "${GREEN}Cleanup complete!${NC}"

# Show remaining containers
echo -e "${BLUE}Remaining containers:${NC}"
podman ps -a