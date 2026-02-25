#!/bin/bash
# This script manages the test environment using podman-compose.
# It provides a simple interface to start, stop, and view logs
# for the test containers defined in podman-compose.yml.
set -e

COMPOSE_FILE="podman-compose.yml"

case "$1" in
  up)
    echo "Starting services with clean state..."
    podman-compose -f "$COMPOSE_FILE" down --volumes --remove-orphans
    podman-compose -f "$COMPOSE_FILE" up -d
    echo "Services started. Monitor with: podman-compose logs -f"
    ;;
  down)
    echo "Stopping and cleaning services..."
    podman-compose -f "$COMPOSE_FILE" down --volumes --remove-orphans
    ;;
  restart)
    echo "Restarting services..."
    podman-compose -f "$COMPOSE_FILE" down --volumes --remove-orphans
    podman-compose -f "$COMPOSE_FILE" up -d
    ;;
  logs)
    podman-compose -f "$COMPOSE_FILE" logs -f
    ;;
  *)
    echo "Usage: $0 {up|down|restart|logs}"
    exit 1
    ;;
esac