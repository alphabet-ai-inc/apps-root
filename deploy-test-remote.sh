#!/bin/bash

# Remote test deployment entrypoint (/opt).

set -euo pipefail

echo "🚀 Test deploy started..."

required_vars=(
  GITHUB_TOKEN
  POSTGRES_USER
  POSTGRES_PASSWORD
  POSTGRES_DB
  POSTGRES_HOST
  POSTGRES_PORT
  JWT_SECRET
  JWT_ISSUER
  JWT_AUDIENCE
  SESSION_AUTH_KEY
  SESSION_ENCRYPTION_KEY
  DOMAIN
  COOKIE_DOMAIN
  ALLOWED_ORIGINS
  APP_PORT
  VITE_BACKEND_URL
)

for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "Missing required env var: $v"
    exit 1
  fi
done

# Disable systemd integration for podman-compose to prevent automatic stopping
export PODMAN_COMPOSE_NO_SYSTEMD=1

cd /opt

git config --global credential.helper store
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > ~/.git-credentials
chmod 600 ~/.git-credentials

for repo in authserver apps-root; do
  if [ -d "$repo/.git" ]; then
    (cd "$repo" && git pull origin main)
  fi
done

cp -f apps-root/podman-compose.test.yml /opt/podman-compose.yml

cat > authserver/database/.env << EOF
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
POSTGRES_EXTERNAL_PORT=$POSTGRES_PORT
POSTGRES_HOST=$POSTGRES_HOST
EOF

cat > authserver/backend/.env << EOF
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
POSTGRES_EXTERNAL_PORT=$POSTGRES_PORT
POSTGRES_HOST=$POSTGRES_HOST
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

cat > authserver/frontend/.env << EOF
VITE_BACKEND_URL=$VITE_BACKEND_URL
EOF

cd authserver/backend
go mod download
CGO_ENABLED=0 GOOS=linux go build -o authserver .
cd ../frontend
npm ci --silent
npm run buildgit
cd /opt

podman build -t localhost/authserver-test-backend -f authserver/backend/Dockerfile authserver/backend
podman build -t localhost/authserver-test-frontend -f authserver/frontend/Dockerfile authserver/frontend

export DB_PASSWORD="$POSTGRES_PASSWORD"
podman-compose -f podman-compose.yml --project-name opt build authserver-test-backend authserver-test-frontend
podman-compose -f podman-compose.yml --project-name opt up -d authserver-test-backend authserver-test-frontend

# Wait for backend to be ready
echo "Waiting for backend to be ready..."
MAX_RETRIES=10
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if wget --quiet --tries=1 --spider http://127.0.0.1:8081/health; then
        echo "Backend is ready!"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 3
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "Backend failed to start within timeout"
    podman-compose -f podman-compose.yml --project-name opt logs authserver-test-backend
    exit 1
fi

rm -f ~/.git-credentials
git config --global --unset credential.helper || true

echo "✅ Test deploy complete"
