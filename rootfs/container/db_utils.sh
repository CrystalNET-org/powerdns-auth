#!/bin/bash
#
# This script provides shared database utility functions
# to be sourced by other scripts. It is not meant to be
# executed directly.
#

_db_log() {
    # Logs a message with a timestamp and a specific tag.
    local script_name="$1"
    local message="$2"
    echo "$(date +"%Y-%m-%d %H:%M:%S") [$script_name] - $message"
}

# This function checks the database connection *once* and returns an exit code.
# It does not wait or retry.
# Arguments:
#   $1: The name of the calling script (e.g., "Entrypoint", "Readiness") for logging.
check_db_connection() {
    local log_tag="$1"
    if [ -z "$log_tag" ]; then
        log_tag="DB_Check"
    fi

    if [ -n "$PDNS_GMYSQL_HOST" ]; then
        # MySQL Check
        if ! mysqladmin ping -h"$PDNS_GMYSQL_HOST" -P"${PDNS_GMYSQL_PORT:-3306}" -u"$PDNS_GMYSQL_USER" -p"$PDNS_GMYSQL_PASSWORD" &>/dev/null; then
            _db_log "$log_tag" "MySQL connection check FAILED for $PDNS_GMYSQL_HOST"
            return 1
        else
            _db_log "$log_tag" "MySQL connection check OK for $PDNS_GMYSQL_HOST"
            return 0
        fi
    elif [ -n "$PDNS_GPGSQL_HOST" ]; then
        # PostgreSQL Check
        export PGPASSWORD="$PDNS_GPGSQL_PASSWORD"
        if ! pg_isready -h "$PDNS_GPGSQL_HOST" -p "${PDNS_GPGSQL_PORT:-5432}" -U "$PDNS_GPGSQL_USER" -d "$PDNS_GPGSQL_DBNAME" -q; then
            _db_log "$log_tag" "PostgreSQL connection check FAILED for $PDNS_GPGSQL_HOST"
            unset PGPASSWORD
            return 1
        else
            _db_log "$log_tag" "PostgreSQL connection check OK for $PDNS_GPGSQL_HOST"
            unset PGPASSWORD
            return 0
        fi
    else
        _db_log "$log_tag" "No gmysql or gpgsql backend configured, skipping DB check."
        return 0 # Not an error, just no DB to check.
    fi
}