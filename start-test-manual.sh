#!/bin/bash

# Manual container startup script for authserver test
# EMERGENCY USE ONLY - assumes environment is already initialized
# Does NOT: backup, restore, clone, configure, or modify anything

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 EMERGENCY: Manual startup of authserver test${NC}"
echo -e "${YELLOW}⚠️  Use only when CI/CD fails and environment is already set up${NC}"
echo

# Go to test directory
cd /opt/authserver || {
    echo -e "${RED}❌ Cannot access /opt/authserver${NC}"
    exit 1
}

# Start containers (that's it!)
echo -e "${YELLOW}Starting containers...${NC}"
podman-compose -f podman-compose.yml --project-name opt up -d

echo -e "${GREEN}✅ Containers started${NC}"

# Show status
echo -e "${BLUE}Status:${NC}"
podman ps --filter "label=com.docker.compose.project=opt" --format "table {{.Names}}\t{{.Status}}"

echo -e "${GREEN}🎉 Test is running!${NC}"