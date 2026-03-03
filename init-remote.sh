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
  APP_PORT
)

for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo -e "${RED}Missing required env var: $v${NC}"
    exit 1
  fi
done

export API_DOMAIN="${API_DOMAIN:-api.${DOMAIN}}"
export VITE_BACKEND_URL="${VITE_BACKEND_URL:-https://${API_DOMAIN}}"

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
mkdir -p /srv
cd /srv

podman-compose -f podman-compose.yml --project-name srv down 2>/dev/null || true

# Targeted cleanup for production environment (authserver containers but not test)
echo -e "${YELLOW}Removing production authserver containers (excluding test)...${NC}"
podman stop $(podman ps -aq --filter name=authserver --filter name!=test 2>/dev/null) 2>/dev/null || true
podman rm --force $(podman ps -aq --filter name=authserver --filter name!=test 2>/dev/null) 2>/dev/null || true

echo -e "${YELLOW}Setting up network...${NC}"
podman network rm srv_aztech-network 2>/dev/null || true
podman network create srv_aztech-network

echo -e "${YELLOW}Cleaning repository directories...${NC}"
sudo rm -rf /srv/apps-root /srv/authserver /srv/podman-compose.yml /srv/start-manual.sh /srv/stop-manual.sh /srv/init-remote.sh 2>/dev/null || \
  rm -rf /srv/apps-root /srv/authserver /srv/podman-compose.yml /srv/start-manual.sh /srv/stop-manual.sh /srv/init-remote.sh

echo -e "${YELLOW}Cloning repositories...${NC}"
AUTH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com"
git clone "${AUTH_URL}/${GITHUB_ORG}/${APPS_ROOT_REPO}.git" /srv/apps-root
git clone "${AUTH_URL}/${AUTH_REPO}" /srv/authserver

echo -e "${YELLOW}Preparing compose and backups...${NC}"
cp -f /srv/apps-root/podman-compose.yml /srv/podman-compose.yml
cp -f /srv/apps-root/start-manual.sh /srv/start-manual.sh
cp -f /srv/apps-root/stop-manual.sh /srv/stop-manual.sh
cp -f /srv/apps-root/init-remote.sh /srv/init-remote.sh
chmod +x /srv/start-manual.sh /srv/stop-manual.sh /srv/init-remote.sh
sed -i 's|image: postgres:18|image: localhost/srv_authserver-db:latest|' /srv/podman-compose.yml
cp /srv/authserver/database/*backup*.sql /tmp/ 2>/dev/null || true

echo -e "${YELLOW}Running start-manual.sh with CI environment...${NC}"
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

# Explicitly export all required variables for start-manual.sh
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
export APP_PORT
export VITE_BACKEND_URL
export API_DOMAIN

cd /srv
bash /srv/start-manual.sh

echo -e "${GREEN}✅ Remote init completed${NC}"
