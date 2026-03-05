#!/bin/bash

# Manual container startup script for authserver
# This script sets up and starts all containers for local/cloud testing

set -e  # Exit on any error

echo "🚀 Starting manual authserver container setup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (can be overridden by environment variables)
export POSTGRES_USER="${POSTGRES_USER:-authuser}"
export DB_PASSWORD="${DB_PASSWORD:-authpass123}"
export POSTGRES_DB="${POSTGRES_DB:-authserver}"
export JWT_SECRET="${JWT_SECRET:-your-super-secret-jwt-key-change-this-in-production}"
export JWT_ISSUER="${JWT_ISSUER:-authserver}"
export JWT_AUDIENCE="${JWT_AUDIENCE:-authserver}"
export SESSION_AUTH_KEY="${SESSION_AUTH_KEY:-your-session-auth-key-32-chars-minimum}"
export SESSION_ENCRYPTION_KEY="${SESSION_ENCRYPTION_KEY:-your-session-encryption-key-32-chars}"
export COOKIE_DOMAIN="${COOKIE_DOMAIN:-localhost}"
export DOMAIN="${DOMAIN:-localhost}"
export API_DOMAIN="${API_DOMAIN:-api.$DOMAIN}"
export ALLOWED_ORIGINS="${ALLOWED_ORIGINS:-http://localhost:3000,https://app.auth.aztech-ai.com,https://auth.aztech-ai.com}"
export APP_PORT="${APP_PORT:-8080}"
export VITE_BACKEND_URL="${VITE_BACKEND_URL:-http://localhost:8080}"
export AUTH_REPO_URL="${AUTH_REPO_URL:-https://github.com/alphabet-ai-inc/authserver.git}"

# For cloud deployment, use the actual API domain
if [ "$DOMAIN" != "localhost" ]; then
    export VITE_BACKEND_URL="https://$API_DOMAIN"
fi

echo -e "${BLUE}Using configuration:${NC}"
echo "POSTGRES_USER: $POSTGRES_USER"
echo "POSTGRES_DB: $POSTGRES_DB"
echo "APP_PORT: $APP_PORT"
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

if ! command_exists git; then
    echo -e "${RED}Error: git is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}Prerequisites OK${NC}"

# Clone repositories if not already cloned
if [ ! -d "authserver/.git" ]; then
    echo -e "${YELLOW}Cloning authserver repository...${NC}"
    git clone "$AUTH_REPO_URL" authserver
    echo -e "${GREEN}Repository cloned${NC}"
else
    echo -e "${BLUE}Authserver repository already exists${NC}"
fi

# Create directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p authserver/database
mkdir -p authserver/backend
mkdir -p authserver/frontend
echo -e "${GREEN}Directories created${NC}"

# Create .env files
echo -e "${YELLOW}Creating .env files...${NC}"

# Database .env
cat > authserver/database/.env << EOF
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$DB_PASSWORD
POSTGRES_DB=$POSTGRES_DB
POSTGRES_EXTERNAL_PORT=5432
POSTGRES_HOST=localhost
EOF

# Backend .env
cat > authserver/backend/.env << EOF
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$DB_PASSWORD
POSTGRES_DB=$POSTGRES_DB
POSTGRES_EXTERNAL_PORT=5432
POSTGRES_HOST=authserver-db
JWT_SECRET=$JWT_SECRET
JWT_ISSUER=$JWT_ISSUER
JWT_AUDIENCE=$JWT_AUDIENCE
SESSION_AUTH_KEY=$SESSION_AUTH_KEY
SESSION_ENCRYPTION_KEY=$SESSION_ENCRYPTION_KEY
COOKIE_DOMAIN=$COOKIE_DOMAIN
DOMAIN=$DOMAIN
ALLOWED_ORIGINS=$ALLOWED_ORIGINS
PORT=$APP_PORT
EOF

# Frontend .env
cat > authserver/frontend/.env << EOF
VITE_BACKEND_URL=$VITE_BACKEND_URL
EOF

echo -e "${GREEN}.env files created${NC}"

# Copy database backup files to /tmp for restore step (same behavior as init.yml)
echo -e "${YELLOW}Preparing database backup files...${NC}"
cp authserver/database/*backup*.sql /tmp/ 2>/dev/null || true

# Create podman network (if it doesn't exist)
echo -e "${YELLOW}Setting up podman network...${NC}"
if podman network ls --format "{{.Name}}" | grep -q "^srv_aztech-network$"; then
    echo -e "${BLUE}Network srv_aztech-network already exists, reusing it${NC}"
else
    podman network create srv_aztech-network
    echo -e "${GREEN}Network created${NC}"
fi

# Build containers
echo -e "${YELLOW}Building database container...${NC}"
cd authserver/database
podman build -t localhost/srv_authserver-db:latest .
cd ..
echo -e "${GREEN}Database container built${NC}"

echo -e "${YELLOW}Building backend container...${NC}"
cd backend
go mod download
CGO_ENABLED=0 GOOS=linux go build -o authserver .
podman build -t localhost/srv_authserver-backend:latest .
cd ..
echo -e "${GREEN}Backend container built${NC}"

echo -e "${YELLOW}Building frontend container...${NC}"
cd frontend
npm ci --silent
npm run build
podman build -t localhost/srv_authserver-frontend:latest .
cd ..
echo -e "${GREEN}Frontend container built${NC}"

# Go back to apps-root directory
cd ..

# Start database first
echo -e "${YELLOW}Starting database container...${NC}"
podman-compose -f podman-compose.yml --project-name srv up -d authserver-db

# Wait for database to be ready
echo -e "${YELLOW}Waiting for database to be ready...${NC}"
MAX_RETRIES=10
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if podman exec srv_authserver-db_1 pg_isready -U "$POSTGRES_USER" -h localhost > /dev/null 2>&1; then
        echo -e "${GREEN}Database is ready!${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 3
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}Database failed to start within timeout${NC}"
    podman logs srv_authserver-db_1
    exit 1
fi

# Initialize database user and permissions
echo -e "${YELLOW}Initializing database user and permissions...${NC}"

# Note: When POSTGRES_USER is set, that user becomes the superuser, not 'postgres'
# So we connect as the configured user instead of 'postgres'

# Create user if it doesn't exist (but it should already exist as superuser)
if podman exec srv_authserver-db_1 psql -U "$POSTGRES_USER" -d postgres -t -c "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = '$POSTGRES_USER');" | grep -q " t"; then
    echo "User $POSTGRES_USER already exists as superuser, ensuring password is correct..."
    podman exec srv_authserver-db_1 psql -U "$POSTGRES_USER" -d postgres -c "ALTER USER \"$POSTGRES_USER\" WITH PASSWORD '$DB_PASSWORD';"
    echo "Password updated for user $POSTGRES_USER"
else
    echo "User $POSTGRES_USER should already exist as superuser from Docker image"
fi

# Create database if it doesn't exist
if podman exec srv_authserver-db_1 psql -U "$POSTGRES_USER" -d postgres -t -c "SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB');" | grep -q " t"; then
    echo "Database $POSTGRES_DB already exists"
else
    echo "Creating database $POSTGRES_DB..."
    podman exec srv_authserver-db_1 psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$POSTGRES_DB\";"
fi

# === RESTORE DATABASE BACKUP IF EXISTS (same logic as init.yml) ===
echo -e "${YELLOW}Checking for database backup...${NC}"
LATEST_BACKUP=$(ls -t /tmp/authserver*_backup.sql 2>/dev/null | head -1)
if [ -n "$LATEST_BACKUP" ] && [ -f "$LATEST_BACKUP" ]; then
    echo "Restoring from $LATEST_BACKUP"
    # Backup can include CREATE/ALTER ROLE and CREATE/ALTER DATABASE statements
    # that fail when user/database already exist in the target environment.
    awk -v u="$POSTGRES_USER" -v db="$POSTGRES_DB" 'BEGIN{IGNORECASE=1} {
        line=$0
        gsub(/"/, "", line)
        if (line ~ "^[[:space:]]*(CREATE ROLE|CREATE USER|ALTER ROLE)[[:space:]]+" u "([[:space:]]|;|$)") next
        if (line ~ "^[[:space:]]*CREATE[[:space:]]+DATABASE[[:space:]]+" db "([[:space:]]|;|$)") next
        if (line ~ "^[[:space:]]*ALTER[[:space:]]+DATABASE[[:space:]]+" db "([[:space:]]|;|$)") next
        print
    }' "$LATEST_BACKUP" \
        | podman exec -i srv_authserver-db_1 psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"
    echo -e "${GREEN}Database backup restored${NC}"

    # Ensure user password is set to current value after restore
    podman exec srv_authserver-db_1 psql -U "$POSTGRES_USER" -d postgres -c "ALTER USER \"$POSTGRES_USER\" WITH PASSWORD '$DB_PASSWORD';"
else
    echo "No backup found at /tmp/authserver*_backup.sql"
fi

# Set database owner
podman exec srv_authserver-db_1 psql -U "$POSTGRES_USER" -d postgres -c "ALTER DATABASE \"$POSTGRES_DB\" OWNER TO \"$POSTGRES_USER\";"

# Configure SCRAM-SHA-256 authentication
echo -e "${YELLOW}Configuring SCRAM-SHA-256 authentication...${NC}"
podman exec srv_authserver-db_1 psql -U "$POSTGRES_USER" -d postgres -c "ALTER SYSTEM SET password_encryption = 'scram-sha-256';"

# Update pg_hba.conf
echo -e "${YELLOW}Updating pg_hba.conf...${NC}"
podman exec srv_authserver-db_1 bash -c "
    echo '# TYPE  DATABASE        USER            ADDRESS                 METHOD' > \$PGDATA/pg_hba.conf
    echo '    local   all             all                                     trust' >> \$PGDATA/pg_hba.conf
    echo '    host    all             all             127.0.0.1/32            scram-sha-256' >> \$PGDATA/pg_hba.conf
    echo '    host    all             all             ::1/128                 scram-sha-256' >> \$PGDATA/pg_hba.conf
    echo '    host    all             all             0.0.0.0/0               scram-sha-256' >> \$PGDATA/pg_hba.conf
    chown postgres:postgres \$PGDATA/pg_hba.conf
    chmod 600 \$PGDATA/pg_hba.conf
"

# Reload PostgreSQL configuration
podman exec srv_authserver-db_1 psql -U "$POSTGRES_USER" -d postgres -c "SELECT pg_reload_conf();"

echo -e "${GREEN}Database initialization complete${NC}"

# Test database connection
echo -e "${YELLOW}Testing database connection...${NC}"
if podman exec srv_authserver-db_1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${GREEN}Database connection test successful${NC}"
else
    echo -e "${RED}Database connection test failed${NC}"
    echo "Trying to connect to postgres database instead..."
    if podman exec srv_authserver-db_1 psql -U "$POSTGRES_USER" -d postgres -c "SELECT version();" > /dev/null 2>&1; then
        echo -e "${YELLOW}Connection to postgres database works, but not to $POSTGRES_DB${NC}"
    else
        echo -e "${RED}Cannot connect to database at all${NC}"
    fi
fi

# Start remaining services
echo -e "${YELLOW}Starting remaining services...${NC}"
echo -e "${BLUE}Environment variables being passed to podman-compose:${NC}"
echo "POSTGRES_USER=$POSTGRES_USER"
echo "DB_PASSWORD=$DB_PASSWORD"
echo "POSTGRES_DB=$POSTGRES_DB"
echo "JWT_SECRET=${JWT_SECRET:0:20}..."
echo "ALLOWED_ORIGINS=$ALLOWED_ORIGINS"
echo "VITE_BACKEND_URL=$VITE_BACKEND_URL"
podman-compose -f podman-compose.yml --project-name srv up -d authserver-backend authserver-frontend

echo -e "${GREEN}Services started!${NC}"

# Wait a bit for services to start
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
sleep 10

# Check status
echo -e "${BLUE}Container status:${NC}"
podman ps --filter "label=com.docker.compose.project=srv"

echo ""
echo -e "${GREEN}🎉 Setup complete!${NC}"
echo ""
echo -e "${BLUE}Services should be available at:${NC}"
echo "Frontend: http://localhost:3000"
echo "Backend: http://localhost:8080"
echo "Database: localhost:5432"
echo ""
echo -e "${YELLOW}To check logs:${NC}"
echo "podman-compose -f podman-compose.yml --project-name srv logs -f"
echo ""
echo -e "${YELLOW}To stop services:${NC}"
echo "podman-compose -f podman-compose.yml --project-name srv down"