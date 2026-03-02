#!/bin/bash

# Manual container startup script for authserver TEST environment
# This script sets up and starts all containers for test environment

set -e  # Exit on any error

echo "🚀 Starting manual authserver TEST container setup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (can be overridden by environment variables)
export POSTGRES_USER="${POSTGRES_USER:-authuser}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-authpass123}"
export POSTGRES_DB="${POSTGRES_DB:-authserver}"
export JWT_SECRET="${JWT_SECRET:-your-super-secret-jwt-key-change-this-in-production}"
export JWT_ISSUER="${JWT_ISSUER:-authserver}"
export JWT_AUDIENCE="${JWT_AUDIENCE:-authserver}"
export SESSION_AUTH_KEY="${SESSION_AUTH_KEY:-your-session-auth-key-32-chars-minimum}"
export SESSION_ENCRYPTION_KEY="${SESSION_ENCRYPTION_KEY:-your-session-encryption-key-32-chars}"
export COOKIE_DOMAIN="${COOKIE_DOMAIN:-test.auth.aztech-ai.com}"
export DOMAIN="${DOMAIN:-test.auth.aztech-ai.com}"
export ALLOWED_ORIGINS="${ALLOWED_ORIGINS:-https://app.test.auth.aztech-ai.com,https://api.test.auth.aztech-ai.com}"
export TEST_BACKEND_PORT="${TEST_BACKEND_PORT:-8081}"
export VITE_BACKEND_URL="${VITE_BACKEND_URL:-https://api.test.auth.aztech-ai.com}"

echo -e "${BLUE}Using TEST configuration:${NC}"
echo "POSTGRES_USER: $POSTGRES_USER"
echo "POSTGRES_DB: ${POSTGRES_DB}_test"
echo "TEST_BACKEND_PORT: $TEST_BACKEND_PORT"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
if ! command_exists podman; then
    echo -e "${RED}Error: podman is not installed${NC}"
    exit 1
fi

if ! command_exists podman-compose; then
    echo -e "${RED}Error: podman-compose is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}Prerequisites OK${NC}"

# Change to /opt directory
cd /opt

# Create podman network (if it doesn't exist)
echo -e "${YELLOW}Setting up podman test network...${NC}"
if podman network ls --format "{{.Name}}" | grep -q "^aztech-test-network$"; then
    echo -e "${BLUE}Network aztech-test-network already exists, reusing it${NC}"
else
    podman network create aztech-test-network
    echo -e "${GREEN}Network created${NC}"
fi

# Database should already be started by init-test-remote.sh
# Just verify it's ready
echo -e "${YELLOW}Verifying test database is ready...${NC}"
if podman exec authserver-test-db pg_isready -U "$POSTGRES_USER" -d postgres > /dev/null 2>&1; then
    echo -e "${GREEN}Database is ready!${NC}"
else
    echo -e "${RED}Database is not ready, waiting...${NC}"
    MAX_RETRIES=5
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if podman exec authserver-test-db pg_isready -U "$POSTGRES_USER" -d postgres > /dev/null 2>&1; then
            echo -e "${GREEN}Database is ready!${NC}"
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Waiting... ($RETRY_COUNT/$MAX_RETRIES)"
        sleep 2
    done

    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo -e "${RED}Database failed to be ready${NC}"
        podman logs authserver-test-db
        exit 1
    fi
fi

# Initialize database user and permissions
echo -e "${YELLOW}Initializing test database user and permissions...${NC}"

TEST_DB_NAME="${POSTGRES_DB}_test"

# Create database if it doesn't exist
if podman exec authserver-test-db psql -U "$POSTGRES_USER" -d postgres -t -c "SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname = '$TEST_DB_NAME');" | grep -q " t"; then
    echo "Database $TEST_DB_NAME already exists"
else
    echo "Creating database $TEST_DB_NAME..."
    podman exec authserver-test-db psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$TEST_DB_NAME\";"
fi

# === RESTORE DATABASE BACKUP IF EXISTS (same logic as init.yml) ===
echo -e "${YELLOW}Checking for database backup...${NC}"
LATEST_BACKUP=$(ls -t /tmp/authserver*_backup.sql 2>/dev/null | head -1)
if [ -n "$LATEST_BACKUP" ] && [ -f "$LATEST_BACKUP" ]; then
    echo "Restoring from $LATEST_BACKUP"
    # Backup can include CREATE/ALTER ROLE and CREATE/ALTER DATABASE statements
    # that fail when user/database already exist in the target environment.
    awk -v u="$POSTGRES_USER" -v db="$TEST_DB_NAME" 'BEGIN{IGNORECASE=1} {
        line=$0
        gsub(/"/, "", line)
        if (line ~ "^[[:space:]]*(CREATE ROLE|CREATE USER|ALTER ROLE)[[:space:]]+" u "([[:space:]]|;|$)") next
        if (line ~ "^[[:space:]]*CREATE[[:space:]]+DATABASE[[:space:]]+" db "([[:space:]]|;|$)") next
        if (line ~ "^[[:space:]]*ALTER[[:space:]]+DATABASE[[:space:]]+" db "([[:space:]]|;|$)") next
        print
    }' "$LATEST_BACKUP" \
        | podman exec -i authserver-test-db psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$TEST_DB_NAME"
    echo -e "${GREEN}Database backup restored${NC}"

    # Ensure user password is set to current value after restore
    podman exec authserver-test-db psql -U "$POSTGRES_USER" -d postgres -c "ALTER USER \"$POSTGRES_USER\" WITH PASSWORD '$POSTGRES_PASSWORD';"
else
    echo "No backup found at /tmp/authserver*_backup.sql"
fi

# Set database owner
podman exec authserver-test-db psql -U "$POSTGRES_USER" -d postgres -c "ALTER DATABASE \"$TEST_DB_NAME\" OWNER TO \"$POSTGRES_USER\";"

# Configure SCRAM-SHA-256 authentication
echo -e "${YELLOW}Configuring SCRAM-SHA-256 authentication...${NC}"
podman exec authserver-test-db psql -U "$POSTGRES_USER" -d postgres -c "ALTER SYSTEM SET password_encryption = 'scram-sha-256';"

# Update pg_hba.conf
echo -e "${YELLOW}Updating pg_hba.conf...${NC}"
podman exec authserver-test-db bash -c "
    echo '# TYPE  DATABASE        USER            ADDRESS                 METHOD' > \$PGDATA/pg_hba.conf
    echo '    local   all             all                                     trust' >> \$PGDATA/pg_hba.conf
    echo '    host    all             all             127.0.0.1/32            scram-sha-256' >> \$PGDATA/pg_hba.conf
    echo '    host    all             all             ::1/128                 scram-sha-256' >> \$PGDATA/pg_hba.conf
    echo '    host    all             all             0.0.0.0/0               scram-sha-256' >> \$PGDATA/pg_hba.conf
    chown postgres:postgres \$PGDATA/pg_hba.conf
    chmod 600 \$PGDATA/pg_hba.conf
"

# Reload PostgreSQL configuration
podman exec authserver-test-db psql -U "$POSTGRES_USER" -d postgres -c "SELECT pg_reload_conf();"

echo -e "${GREEN}Database initialization complete${NC}"

# Test database connection
echo -e "${YELLOW}Testing database connection...${NC}"
if podman exec authserver-test-db psql -U "$POSTGRES_USER" -d "$TEST_DB_NAME" -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${GREEN}Database connection test successful${NC}"
else
    echo -e "${RED}Database connection test failed${NC}"
    echo "Trying to connect to postgres database instead..."
    if podman exec authserver-test-db psql -U "$POSTGRES_USER" -d postgres -c "SELECT version();" > /dev/null 2>&1; then
        echo -e "${YELLOW}Connection to postgres database works, but not to $TEST_DB_NAME${NC}"
    else
        echo -e "${RED}Cannot connect to database at all${NC}"
    fi
fi

# Start remaining services
echo -e "${YELLOW}Starting remaining test services...${NC}"
echo -e "${BLUE}Environment variables being passed to podman-compose:${NC}"
echo "POSTGRES_USER=$POSTGRES_USER"
echo "POSTGRES_DB=${POSTGRES_DB}_test"
echo "JWT_SECRET=${JWT_SECRET:0:20}..."
echo "ALLOWED_ORIGINS=$ALLOWED_ORIGINS"
echo "VITE_BACKEND_URL=$VITE_BACKEND_URL"
podman-compose -f podman-compose.yml --project-name opt up -d authserver-test-backend authserver-test-frontend

echo -e "${GREEN}Test services started!${NC}"

# Wait a bit for services to start
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
sleep 10

# Check status
echo -e "${BLUE}Test container status:${NC}"
podman ps --filter "label=com.docker.compose.project=opt"

echo ""
echo -e "${GREEN}🎉 Test setup complete!${NC}"
echo ""
echo -e "${BLUE}Test services should be available at:${NC}"
echo "Frontend: https://app.test.auth.aztech-ai.com"
echo "Backend: https://api.test.auth.aztech-ai.com"
echo "Database: localhost:5433"
echo ""
echo -e "${YELLOW}To check logs:${NC}"
echo "podman-compose -f podman-compose.yml --project-name opt logs -f"
echo ""
echo -e "${YELLOW}To stop services:${NC}"
echo "bash /opt/stop-test-manual.sh"