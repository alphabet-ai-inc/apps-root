#!/bin/bash

# Manual container stop script for authserver test
# EMERGENCY USE ONLY - assumes environment exists

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🛑 EMERGENCY: Manual stop of authserver test${NC}"
echo -e "${YELLOW}⚠️  Use only when needed${NC}"
echo

# Go to test directory
cd /opt/authserver || {
    echo -e "${RED}❌ Cannot access /opt/authserver${NC}"
    exit 1
}

# Stop containers (that's it!)
echo -e "${YELLOW}Stopping containers...${NC}"
podman-compose -f podman-compose.yml --project-name opt down

echo -e "${GREEN}✅ Containers stopped${NC}"

# Show status
echo -e "${BLUE}Status:${NC}"
podman ps --filter "label=com.docker.compose.project=opt" --format "table {{.Names}}\t{{.Status}}"

echo -e "${GREEN}🛑 Test is stopped${NC}"