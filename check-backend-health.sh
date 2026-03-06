#!/bin/bash

# Backend Health Check Script
# This script checks the health of the authserver backend without affecting container status

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKEND_URL="${BACKEND_URL:-http://localhost:8080}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/health}"
TIMEOUT="${TIMEOUT:-10}"
RETRIES="${RETRIES:-3}"

echo -e "${BLUE}🔍 Checking backend health at ${BACKEND_URL}${HEALTH_ENDPOINT}${NC}"
echo "Timeout: ${TIMEOUT}s, Retries: ${RETRIES}"
echo

# Function to check health
check_health() {
    local attempt=$1
    echo -e "${YELLOW}Attempt ${attempt}/${RETRIES}:${NC}"

    # Use curl to check the health endpoint
    if response=$(curl -s --max-time "${TIMEOUT}" "${BACKEND_URL}${HEALTH_ENDPOINT}" 2>/dev/null); then
        echo -e "${GREEN}✅ HTTP request successful${NC}"

        # Parse the JSON response
        if echo "$response" | jq . >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Valid JSON response${NC}"

            # Extract timestamp and version
            timestamp=$(echo "$response" | jq -r '.timestamp // empty')
            version=$(echo "$response" | jq -r '.version // empty')

            if [ -n "$timestamp" ]; then
                echo -e "${GREEN}✅ Timestamp: ${timestamp}${NC}"
            fi

            if [ -n "$version" ]; then
                echo -e "${GREEN}✅ Version: ${version}${NC}"
            fi

            # Check if status field exists (it shouldn't in our simplified version)
            status=$(echo "$response" | jq -r '.status // empty')
            if [ -n "$status" ]; then
                echo -e "${YELLOW}⚠️  Status field present: ${status}${NC}"
            else
                echo -e "${GREEN}✅ No status field (as expected)${NC}"
            fi

            echo -e "${GREEN}🎉 Backend is healthy!${NC}"
            return 0
        else
            echo -e "${RED}❌ Invalid JSON response${NC}"
            echo "Response: $response"
            return 1
        fi
    else
        echo -e "${RED}❌ HTTP request failed${NC}"
        return 1
    fi
}

# Main health check with retries
success=false
for attempt in $(seq 1 "$RETRIES"); do
    if check_health "$attempt"; then
        success=true
        break
    fi

    if [ "$attempt" -lt "$RETRIES" ]; then
        echo -e "${YELLOW}⏳ Waiting 2 seconds before retry...${NC}"
        sleep 2
    fi
    echo
done

echo
if [ "$success" = true ]; then
    echo -e "${GREEN}✅ BACKEND HEALTH CHECK PASSED${NC}"
    exit 0
else
    echo -e "${RED}❌ BACKEND HEALTH CHECK FAILED${NC}"
    echo -e "${YELLOW}💡 Note: This check does not affect container status${NC}"
    echo -e "${YELLOW}💡 Container will remain 'Up' regardless of this result${NC}"
    exit 1
fi