#!/bin/bash
#
# This script performs a comprehensive READINESS check for the PowerDNS container.
# It checks for:
# 1. Database connectivity (MySQL or PostgreSQL), if configured.
# 2. PowerDNS API responsiveness.
#
# It exits with 0 if all checks pass, or 1 if any check fails.
# This script reads the same PDNS_... env vars as the entrypoint.
set -e

# Source shared database utilities
# shellcheck disable=SC1091
source /container/db_utils.sh

log() {
    # Logs a message.
    echo "$(date +"%Y-%m-%d %H:%M:%S") [Readiness] - $1"
}

check_db() {
    log "Checking database connectivity..."
    # Call the shared function once. It will log its own success/failure.
    # The 'if !' structure handles the return code (0 = success, 1 = failure)
    if ! check_db_connection "Readiness"; then
        log "Database readiness check FAILED."
        exit 1
    else
        log "Database readiness check OK."
    fi
}

check_api() {
    log "Checking PowerDNS API..."
    
    # Use default values if env vars are not set
    local api_host="${PDNS_WEB_SERVER_ADDRESS:-127.0.0.1}"
    local api_port="${PDNS_WEB_SERVER_PORT:-8081}"
    local api_key="${PDNS_API_KEY}" # No default for API key
    local api_url="http://${api_host}:${api_port}/api/v1/servers/localhost"

    if [ -z "$api_key" ]; then
        log "PDNS_API_KEY is not set. API readiness check is not possible."
        # Depending on your policy, you might 'exit 1' here.
        # For now, we'll log a warning and skip.
        log "Warning: Skipping API check."
        return
    fi
    
    # We use 'curl' which is a common dependency.
    # -f: Fail silently (exit 1) on server errors (4xx, 5xx)
    # -s: Silent mode
    # -S: Show error if -f fails
    # --connect-timeout 5: Max 5s to connect
    # -m 10: Max 10s for the whole operation
    if ! curl -fsS --connect-timeout 5 -m 10 -H "X-API-Key: $api_key" "$api_url" > /dev/null; then
        log "PowerDNS API check FAILED at $api_url"
        exit 1
    else
        log "PowerDNS API check OK"
    fi
}

# --- Main Readiness Check Execution ---
check_db
check_api

log "All readiness checks passed."
exit 0