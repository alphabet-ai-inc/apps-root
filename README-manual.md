# Manual Authserver Container Setup

This directory contains scripts to manually start and stop the authserver containers for local testing.

## Prerequisites

- `podman` and `podman-compose` installed
- `git` installed
- `go` installed (for building backend)
- `npm`/`node` installed (for building frontend)

## Quick Start

1. **Start all services:**
   ```bash
   ./start-manual.sh
   ```

2. **Check status:**
   ```bash
   podman ps
   ```

3. **View logs:**
   ```bash
   podman-compose -f podman-compose.yml --project-name srv logs -f
   ```

4. **Stop all services:**
   ```bash
   ./stop-manual.sh
   ```

## Services

After starting, services will be available at:

- **Frontend:** http://localhost:3000
- **Backend:** http://localhost:8080
- **Database:** localhost:5432

## Configuration

The `start-manual.sh` script uses test/default values. To customize:

1. Edit the environment variables at the top of `start-manual.sh`
2. Or modify the `.env` files after they are created

## Troubleshooting

- **Permission issues:** Make sure you're not running as root
- **Port conflicts:** Change ports in `podman-compose.yml` if needed
- **Build failures:** Check that all dependencies are installed
- **Database connection issues:** Verify the POSTGRES_USER and password match

## What's Included

- `start-manual.sh` - Complete setup and startup script
- `stop-manual.sh` - Cleanup and shutdown script
- `podman-compose.yml` - Container orchestration configuration