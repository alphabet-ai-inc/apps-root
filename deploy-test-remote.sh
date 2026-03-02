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

cd /opt

git config --global credential.helper store
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > ~/.git-credentials
chmod 600 ~/.git-credentials

for repo in authserver apps-root aztech-caddy; do
  if [ -d "$repo/.git" ]; then
    (cd "$repo" && git pull origin main)
  fi
done

sed -i 's/authserver-backend/authserver-test-backend/g' aztech-caddy/Caddyfile || true
sed -i 's/authserver-frontend/authserver-test-frontend/g' aztech-caddy/Caddyfile || true
sed -i 's/authserver-db/authserver-test-db/g' aztech-caddy/Caddyfile || true

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
npm run build
cd /opt

podman build -t localhost/authserver-test-backend -f authserver/backend/Dockerfile authserver/backend
podman build -t localhost/authserver-test-frontend -f authserver/frontend/Dockerfile authserver/frontend

export DB_PASSWORD="$POSTGRES_PASSWORD"
podman-compose -f podman-compose.yml --project-name opt build authserver-test-backend authserver-test-frontend
podman-compose -f podman-compose.yml --project-name opt up -d authserver-test-backend authserver-test-frontend

podman stop aztech-caddy || true
if podman run --rm -v /opt/aztech-caddy/Caddyfile:/etc/caddy/Caddyfile:ro aztech-caddy:latest caddy validate --config /etc/caddy/Caddyfile; then
  podman start aztech-caddy || true
else
  echo "Caddyfile validation failed"
  exit 1
fi

rm -f ~/.git-credentials
git config --global --unset credential.helper || true

echo "✅ Test deploy complete"
