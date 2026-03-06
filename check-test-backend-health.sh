#!/bin/bash

# Test Backend Health Check Script for Podman Health Checks
# Silent version for container health monitoring

# Check if silent mode is requested
if [ "${SILENT}" = "1" ]; then
    # Silent mode for container health checks
    BACKEND_URL="${BACKEND_URL:-http://localhost:8081}"
    HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/health}"
    TIMEOUT="${TIMEOUT:-10}"

    if curl -s --max-time "${TIMEOUT}" "${BACKEND_URL}${HEALTH_ENDPOINT}" >/dev/null 2>&1; then
        exit 0  # Healthy
    else
        exit 1  # Unhealthy
    fi
fi

# Verbose mode for manual checking
BACKEND_URL="${BACKEND_URL:-http://localhost:8081}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/health}"
TIMEOUT="${TIMEOUT:-10}"

echo "🔍 Checking TEST backend health at ${BACKEND_URL}${HEALTH_ENDPOINT}"

if curl -s --max-time "${TIMEOUT}" "${BACKEND_URL}${HEALTH_ENDPOINT}" >/dev/null 2>&1; then
    echo "✅ TEST backend is responding"
    exit 0
else
    echo "❌ TEST backend is not responding"
    exit 1
fi