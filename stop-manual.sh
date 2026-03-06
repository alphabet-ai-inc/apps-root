#!/bin/bash

# Manual container stop script for authserver production
# EMERGENCY USE ONLY - assumes environment exists

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🛑 EMERGENCY: Manual stop of authserver production${NC}"
echo -e "${YELLOW}⚠️  Use only when needed${NC}"
echo

# Go to production directory
cd /srv/authserver || {
    echo -e "${RED}❌ Cannot access /srv/authserver${NC}"
    exit 1
}

# Stop containers (that's it!)
echo -e "${YELLOW}Stopping containers...${NC}"
podman-compose -f podman-compose.yml --project-name srv down

echo -e "${GREEN}✅ Containers stopped${NC}"

# Show status
echo -e "${BLUE}Status:${NC}"
podman ps --filter "label=com.docker.compose.project=srv" --format "table {{.Names}}\t{{.Status}}"

echo -e "${GREEN}🛑 Production is stopped${NC}"