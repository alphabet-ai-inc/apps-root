# Emergency Manual Authserver Scripts

**EMERGENCY USE ONLY** - These scripts are for production/test recovery when CI/CD fails.

## When to Use

Use these scripts **only** when:
- CI/CD deployment fails
- Need immediate container restart
- Cannot wait for automated deployment

## Scripts

### Production Environment
- **`start-manual.sh`**: Reads secrets from Vault and starts production containers
- **`stop-manual.sh`**: Stops production containers

### Test Environment
- **`start-test-manual.sh`**: Reads secrets from Vault and starts test containers
- **`stop-test-manual.sh`**: Stops test containers

## Prerequisites

- Vault CLI installed
- Scripts must be manually copied to `/srv` (production) or `/opt` (test) by administrator
- **SECURITY WARNING**: Scripts contain hardcoded Vault tokens and self-delete after execution

## How to Use

1. **Edit the script** with actual Vault tokens:
   ```bash
   # In start-manual.sh, replace:
   VAULT_TOKEN="YOUR_PRODUCTION_VAULT_TOKEN_HERE"

   # In start-test-manual.sh, replace:
   VAULT_TOKEN="YOUR_TEST_VAULT_TOKEN_HERE"
   ```

2. **Copy to server:**
   ```bash
   scp start-manual.sh admin@production-server:/srv/
   scp start-test-manual.sh admin@test-server:/opt/
   ```

3. **Run on server:**
   ```bash
   # Production
   ./start-manual.sh

   # Test
   ./start-test-manual.sh
   ```

4. **Script automatically deletes itself** after successful execution for security

## What They Do

- Authenticate with Vault
- Read database, auth, and config secrets
- Export secrets as environment variables
- Start/stop containers with proper configuration
- Display container status

## Important Notes

- **SECURITY**: Scripts contain hardcoded secrets and self-delete after successful execution
- Scripts assume `/srv` and `/opt` directories exist with proper setup
- Only handles container start/stop (no backups, restores, or config changes)
- Requires proper Vault permissions for secret access
- **EMERGENCY USE ONLY** - these bypass normal deployment processes
- Scripts must be manually edited with actual tokens before deployment

## What's Included

- `start-remote.sh` - Complete setup and startup script
- `podman-compose.yml` - Container orchestration configuration