#!/bin/bash

# Remote initialization entrypoint for TEST environment (/opt).
# Invoked by authserver init_test workflow.

set -euo pipefail

echo "🚀 Test remote init started..."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

required_vars=(
  GITHUB_TOKEN
  GITHUB_ORG
  AUTH_REPO
  APPS_ROOT_REPO
  POSTGRES_USER
  POSTGRES_PASSWORD
  POSTGRES_DB
  JWT_SECRET
  JWT_ISSUER
  JWT_AUDIENCE
  SESSION_AUTH_KEY
  SESSION_ENCRYPTION_KEY
  COOKIE_DOMAIN
  DOMAIN
  ALLOWED_ORIGINS
)

for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo -e "${RED}Missing required env var: $v${NC}"
    exit 1
  fi
done

TEST_DOMAIN="test.${DOMAIN}"
TEST_BACKEND_URL="${VITE_BACKEND_URL:-https://api.${TEST_DOMAIN}}"
TEST_FRONTEND_URL="https://app.${TEST_DOMAIN}"
TEST_DB_PORT="${TEST_DB_PORT:-5433}"
TEST_BACKEND_PORT="${TEST_BACKEND_PORT:-8081}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

if ! command_exists podman || ! command_exists podman-compose || ! command_exists git; then
  echo -e "${RED}Missing required tools (podman, podman-compose, git)${NC}"
  exit 1
fi

mkdir -p /opt
cd /opt

echo -e "${YELLOW}Cleaning test environment...${NC}"
podman-compose -f podman-compose.yml --project-name opt down 2>/dev/null || true
podman stop authserver-test-db authserver-test-backend authserver-test-frontend 2>/dev/null || true
podman rm -f authserver-test-db authserver-test-backend authserver-test-frontend 2>/dev/null || true
podman volume rm postgres_test_data 2>/dev/null || true
podman rmi localhost/opt_authserver-test-db:latest localhost/opt_authserver-test-backend:latest localhost/opt_authserver-test-frontend:latest 2>/dev/null || true
rm -rf /opt/authserver /opt/apps-root /opt/podman-compose.yml 2>/dev/null || true

echo -e "${YELLOW}Cloning repositories...${NC}"
AUTH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com"
git clone "${AUTH_URL}/${GITHUB_ORG}/${APPS_ROOT_REPO}.git" /opt/apps-root
git clone "${AUTH_URL}/${AUTH_REPO}" /opt/authserver

echo -e "${YELLOW}Preparing compose and scripts...${NC}"
cp -f /opt/apps-root/podman-compose.test.yml /opt/podman-compose.yml
cp -f /opt/apps-root/start-test-manual.sh /opt/start-test-manual.sh
cp -f /opt/apps-root/stop-test-manual.sh /opt/stop-test-manual.sh
cp -f /opt/apps-root/init-test-remote.sh /opt/init-test-remote.sh
chmod +x /opt/start-test-manual.sh /opt/stop-test-manual.sh /opt/init-test-remote.sh
sed -i 's|image: postgres:18|image: localhost/opt_authserver-test-db:latest|' /opt/podman-compose.yml
cp /opt/authserver/database/*backup*.sql /tmp/ 2>/dev/null || true

echo -e "${YELLOW}Creating test environment files...${NC}"
cat > /opt/authserver/database/.env.test << EOF
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=${POSTGRES_DB}_test
POSTGRES_EXTERNAL_PORT=$TEST_DB_PORT
POSTGRES_HOST=authserver-test-db
EOF

cat > /opt/authserver/backend/.env.test << EOF
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=${POSTGRES_DB}_test
POSTGRES_EXTERNAL_PORT=$TEST_DB_PORT
POSTGRES_HOST=authserver-test-db
JWT_SECRET=$JWT_SECRET
JWT_ISSUER=$JWT_ISSUER
JWT_AUDIENCE=$JWT_AUDIENCE
SESSION_AUTH_KEY=$SESSION_AUTH_KEY
SESSION_ENCRYPTION_KEY=$SESSION_ENCRYPTION_KEY
COOKIE_DOMAIN=$TEST_DOMAIN
DOMAIN=$TEST_DOMAIN
ALLOWED_ORIGINS=$TEST_FRONTEND_URL,$TEST_BACKEND_URL
PORT=$TEST_BACKEND_PORT
DISABLE_TLS=true
EOF

cat > /opt/authserver/frontend/.env.test << EOF
VITE_BACKEND_URL=$TEST_BACKEND_URL
VITE_API_URL=$TEST_BACKEND_URL
EOF

cp /opt/authserver/backend/.env.test /opt/authserver/backend/.env
cp /opt/authserver/frontend/.env.test /opt/authserver/frontend/.env

echo -e "${YELLOW}Building test images...${NC}"
cd /opt/authserver/backend
go mod download
CGO_ENABLED=0 GOOS=linux go build -o authserver .
podman build -t localhost/opt_authserver-test-backend:latest .

cd /opt/authserver/frontend
npm ci --silent
npm run build
podman build -t localhost/opt_authserver-test-frontend:latest .

cd /opt/authserver/database
cd /opt

# Create test network if it doesn't exist
podman network create aztech-test-network 2>/dev/null || true

echo -e "${YELLOW}Starting test database...${NC}"
# Start database container manually with explicit environment variables
podman run -d \
  --name authserver-test-db \
  --network aztech-test-network \
  --publish 5433:5432 \
  --volume postgres_test_data:/var/lib/postgresql \
  --env POSTGRES_USER="$POSTGRES_USER" \
  --env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --env POSTGRES_DB=postgres \
  localhost/opt_authserver-test-db:latest \
  postgres -c shared_preload_libraries=pg_stat_statements -c pg_stat_statements.track=all -c pg_stat_statements.max=10000

echo -e "${YELLOW}Waiting for test database readiness...${NC}"
MAX_RETRIES=10
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  # Check if container is running first
  if podman ps --filter "name=authserver-test-db" --filter "status=running" | grep -q authserver-test-db; then
    # Container is running, check if database is ready (suppress error output)
    if podman exec authserver-test-db pg_isready -U "$POSTGRES_USER" -d postgres >/dev/null 2>&1; then
      echo -e "${GREEN}Database is ready!${NC}"
      break
    fi
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "Waiting... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 3
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo -e "${RED}Database failed to become ready${NC}"
  echo "Container status:"
  podman ps --filter "name=authserver-test-db"
  echo "Container logs:"
  podman logs authserver-test-db | tail -20
  exit 1
fi

echo -e "${YELLOW}Running start-test-manual.sh with test environment...${NC}"
export TEST_DB_NAME="${POSTGRES_DB}_test"

# Explicitly export all required variables for start-test-manual.sh
export GITHUB_TOKEN
export GITHUB_ORG
export AUTH_REPO
export APPS_ROOT_REPO
export POSTGRES_USER
export POSTGRES_PASSWORD
export POSTGRES_DB
export JWT_SECRET
export JWT_ISSUER
export JWT_AUDIENCE
export SESSION_AUTH_KEY
export SESSION_ENCRYPTION_KEY
export COOKIE_DOMAIN
export DOMAIN
export ALLOWED_ORIGINS
export TEST_DOMAIN
export TEST_BACKEND_URL
export TEST_FRONTEND_URL
export TEST_DB_PORT
export TEST_BACKEND_PORT
export VITE_BACKEND_URL

cd /opt
bash /opt/start-test-manual.sh

echo -e "${GREEN}✅ Test remote init completed${NC}"
