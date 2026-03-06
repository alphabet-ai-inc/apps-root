#!/bin/bash

# Test Backend Health Check Script
# This script checks the health of the authserver test backend

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration for test environment
BACKEND_URL="${BACKEND_URL:-http://localhost:8081}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/health}"
TIMEOUT="${TIMEOUT:-10}"

echo -e "${BLUE}🔍 Checking TEST backend health at ${BACKEND_URL}${HEALTH_ENDPOINT}${NC}"
echo

# Simple health check
if curl -s --max-time "${TIMEOUT}" "${BACKEND_URL}${HEALTH_ENDPOINT}" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ TEST backend is responding${NC}"
    exit 0
else
    echo -e "${RED}❌ TEST backend is not responding${NC}"
    exit 1
fi