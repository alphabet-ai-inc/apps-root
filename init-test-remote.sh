#!/bin/bash

# Remote initialization entrypoint for CI/CD.
# Keeps workflow YAML small by moving deployment logic here.

set -euo pipefail

echo "🚀 Remote init started..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Required env vars
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

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

echo -e "${YELLOW}Checking prerequisites...${NC}"
if ! command_exists podman; then
  echo -e "${RED}podman is not installed${NC}"
  exit 1
fi
if ! command_exists podman-compose; then
  echo -e "${RED}podman-compose is not installed${NC}"
  exit 1
fi
if ! command_exists git; then
  echo -e "${RED}git is not installed${NC}"
  exit 1
fi

echo -e "${GREEN}Prerequisites OK${NC}"

echo -e "${YELLOW}Cleaning remote environment...${NC}"
mkdir -p /opt
cd /opt

podman-compose -f podman-compose.yml --project-name opt down 2>/dev/null || true
podman stop --all 2>/dev/null || true
podman rm --all --force 2>/dev/null || true
podman volume rm --all --force 2>/dev/null || true
podman rmi --all --force 2>/dev/null || true

echo -e "${YELLOW}Setting up network...${NC}"
podman network rm aztech-test-network 2>/dev/null || true
podman network create aztech-test-network

echo -e "${YELLOW}Cleaning repository directories...${NC}"
rm -rf /opt/apps-root /opt/authserver /opt/podman-compose.yml /opt/start-test-manual.sh /opt/stop-test-manual.sh /opt/init-test-remote.sh

echo -e "${YELLOW}Cloning repositories...${NC}"
AUTH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com"
git clone "${AUTH_URL}/${GITHUB_ORG}/${APPS_ROOT_REPO}.git" /opt/apps-root
git clone "${AUTH_URL}/${AUTH_REPO}" /opt/authserver

echo -e "${YELLOW}Preparing compose and backups...${NC}"
cp -f /opt/apps-root/podman-compose.test.yml /opt/podman-compose.yml
cp -f /opt/apps-root/start-test-manual.sh /opt/start-test-manual.sh
cp -f /opt/apps-root/stop-test-manual.sh /opt/stop-test-manual.sh
cp -f /opt/apps-root/init-test-remote.sh /opt/init-test-remote.sh
chmod +x /opt/start-test-manual.sh /opt/stop-test-manual.sh /opt/init-test-remote.sh
sed -i 's|image: postgres:18|image: localhost/opt_authserver-test-db:latest|' /opt/podman-compose.yml
cp /opt/authserver/database/*backup*.sql /tmp/ 2>/dev/null || true

echo -e "${YELLOW}Running start-test-manual.sh with CI environment...${NC}"
export DB_PASSWORD="$POSTGRES_PASSWORD"
export AUTH_REPO_URL="${AUTH_URL}/${AUTH_REPO}"

# Ensure go, node/npm are in PATH for non-interactive SSH sessions
# (these tools are added via .bashrc which is not sourced in non-interactive SSH)
export PATH="/usr/local/go/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:$PATH"
# Source nvm if present (node version manager)
if [ -f "$HOME/.nvm/nvm.sh" ]; then
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  source "$HOME/.nvm/nvm.sh"
fi

echo "PATH=$PATH"
echo "go:  $(command -v go || echo 'NOT FOUND')"
echo "npm: $(command -v npm || echo 'NOT FOUND')"

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
export TEST_FRONTEND_URL="https://app.${TEST_DOMAIN}"
export TEST_DB_PORT="${TEST_DB_PORT:-5433}"
export TEST_BACKEND_PORT="${TEST_BACKEND_PORT:-8081}"
export VITE_BACKEND_URL

cd /opt
bash /opt/start-test-manual.sh

echo -e "${GREEN}✅ Remote init completed${NC}"
