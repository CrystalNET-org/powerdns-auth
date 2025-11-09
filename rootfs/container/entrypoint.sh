#!/bin/bash
set -e

# Source shared database utilities
# shellcheck disable=SC1091
source /container/db_utils.sh

# --- Utility Functions ---

log() {
    # Logs a message with a timestamp
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

check_required_vars() {
    # Checks if all required environment variables are set
    local required_vars=("$@")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log "Error: $var is not defined. Please set the required environment variables."
            exit 1
        fi
    done
}

# --- MySQL Functions ---

check_mysql_availability() {
    # Waits for the MySQL server to become available
    local max_attempts=30
    local attempt=0
    local mysql_vars=(
        "PDNS_GMYSQL_HOST"
        "PDNS_GMYSQL_PORT"
        "PDNS_GMYSQL_USER"
        "PDNS_GMYSQL_PASSWORD"
        "PDNS_GMYSQL_DBNAME"
    )
    check_required_vars "${mysql_vars[@]}"

    log "Checking MySQL server availability at $PDNS_GMYSQL_HOST:$PDNS_GMYSQL_PORT..."
    while [ "$attempt" -lt "$max_attempts" ]; do
        # Use the shared DB check function
        if check_db_connection "Entrypoint-MySQL"; then
            log "MySQL server is available."
            return
        else
            log "MySQL server is not yet available. Retrying in 5 seconds... (Attempt: $((attempt + 1)))"
            sleep 5
            ((attempt++))
        fi
    done

    log "Error: Unable to connect to MySQL server after $max_attempts attempts. Exiting."
    exit 1
}

# WiP
sync_mysql_schema() {
    # Compares and synchronizes the MySQL schema
    local schema_file="/etc/pdns/mysql_schema.sql"
    local temp_diff_file="/tmp/schema_diff.sql"

    # Verify MySQL-related environment variables
    local mysql_vars=(
        "PDNS_GMYSQL_HOST"
        "PDNS_GMYSQL_PORT"
        "PDNS_GMYSQL_USER"
        "PDNS_GMYSQL_PASSWORD"
        "PDNS_GMYSQL_DBNAME"
    )

    check_required_vars "${mysql_vars[@]}"

    if [ ! -e "$schema_file" ]; then
        log "Error: MySQL schema file $schema_file not found."
        exit 1
    fi

    log "Comparing MySQL schema with local schema.sql file..."

    # Dump current schema and diff it with the blessed schema file
    mysqldump -h"$PDNS_GMYSQL_HOST" -P"$PDNS_GMYSQL_PORT" -u"$PDNS_GMYSQL_USER" -p"$PDNS_GMYSQL_PASSWORD" --no-data "$PDNS_GMYSQL_DBNAME" | diff - "$schema_file" > "$temp_diff_file"

    if [ $? -eq 0 ]; then
        log "MySQL schema is already in sync with the local schema.sql file."
    else
        log "Detected differences in MySQL schema. Synchronizing using pt-table-sync..."
        log "Schema diff:"
        cat "$temp_diff_file"

        # Extract table names from schema.sql
        tables=("$(grep -oP "(?<=CREATE TABLE \`)[^\`]+" "$schema_file")")

        # Synchronize each table (as per user's original script)
        for table in "${tables[@]}"; do
            log "Syncing table: $table"
            # Note: This command attempts to sync a DB table with a .sql file, which may not be the intended use of pt-table-sync.
            pt-table-sync --execute --verbose h="$PDNS_GMYSQL_HOST",P="$PDNS_GMYSQL_PORT",u="$PDNS_GMYSQL_USER",p="$PDNS_GMYSQL_PASSWORD" "$PDNS_GMYSQL_DBNAME"."$table" "$schema_file"
        done
        log "MySQL schema synchronization attempt complete."
    fi

    rm -f "$temp_diff_file"
}

# --- PostgreSQL Functions ---

check_pgsql_availability() {
    # Waits for the PostgreSQL server to become available
    local max_attempts=30
    local attempt=0
    local pgsql_vars=(
        "PDNS_GPGSQL_HOST"
        "PDNS_GPGSQL_PORT"
        "PDNS_GPGSQL_USER"
        "PDNS_GPGSQL_PASSWORD"
        "PDNS_GPGSQL_DBNAME"
    )
    check_required_vars "${pgsql_vars[@]}"

    export PGPASSWORD="$PDNS_GPGSQL_PASSWORD"
    
    log "Checking PostgreSQL server availability at $PDNS_GPGSQL_HOST:$PDNS_GPGSQL_PORT..."
    while [ "$attempt" -lt "$max_attempts" ]; do
        # Use the shared DB check function
        if check_db_connection "Entrypoint-PgSQL"; then
            log "PostgreSQL server is available."
            unset PGPASSWORD
            return
        else
            log "PostgreSQL server is not yet available. Retrying in 5 seconds... (Attempt: $((attempt + 1)))"
            sleep 5
            ((attempt++))
        fi
    done
    
    unset PGPASSWORD
    log "Error: Unable to connect to PostgreSQL server after $max_attempts attempts. Exiting."
    exit 1
}

sync_pgsql_schema() {
    # Compares the PostgreSQL schema and exits if different
    local schema_file="/etc/pdns/pgsql_schema.sql"
    local temp_diff_file="/tmp/schema_diff.sql"
    
    log "Checking for existing PostgreSQL schema in database $PDNS_GPGSQL_DBNAME..."

    if [ ! -e "$schema_file" ]; then
        log "Error: PostgreSQL schema file $schema_file not found."
        exit 1
    fi

    export PGPASSWORD="$PDNS_GPGSQL_PASSWORD"
    
    log "Comparing PostgreSQL schema with local schema.sql file..."
    
    # Dump current schema and diff it with the blessed schema file
    pg_dump -h "$PDNS_GPGSQL_HOST" -p "$PDNS_GPGSQL_PORT" -U "$PDNS_GPGSQL_USER" -d "$PDNS_GPGSQL_DBNAME" --schema-only | diff - "$schema_file" > "$temp_diff_file"

    if [ $? -eq 0 ]; then
        log "PostgreSQL schema is already in sync with the local schema.sql file."
    else
        log "Error: Detected differences in PostgreSQL schema."
        log "Schema diff:"
        cat "$temp_diff_file"
        log "Automatic schema synchronization is not supported for PostgreSQL."
        log "Please apply migrations manually or update the $schema_file."
        unset PGPASSWORD
        exit 1
    fi
    
    unset PGPASSWORD
}


# --- Main Execution ---

# Determine which database backend to use
if [ -n "$PDNS_GMYSQL_HOST" ] && [ -n "$PDNS_GPGSQL_HOST" ]; then
    log "Error: Both PDNS_GMYSQL_HOST and PDNS_GPGSQL_HOST are defined. Please configure only one backend."
    exit 1
elif [ -n "$PDNS_GMYSQL_HOST" ]; then
    log "MySQL backend detected. Running checks..."
    check_mysql_availability
    sync_mysql_schema
elif [ -n "$PDNS_GPGSQL_HOST" ]; then
    log "PostgreSQL backend detected. Running checks..."
    check_pgsql_availability
    sync_pgsql_schema
else
    log "No gmysql or gpgsql backend host defined. Skipping database checks."
    log "Assuming a different backend (e.g., BIND, LUA) or local database."
fi


cmd_args=()

# Read all PDNS_ prefixed environment variables and convert them to command line parameters
while IFS='=' read -r name value; do
    if [[ $name == PDNS_* ]]; then
        # Convert PDNS_VAR_NAME to --var-name=value
        cmd_args+=( "--$(tr '[:upper:]_' '[:lower:]-' <<< "${name#PDNS_}")=$value" )
    fi
done < <(env)

# setup traps for PowerDNS server
# We trap signals and tell pdns_control to quit.
# 'exec' will replace this shell script with the pdns_server process,
# so pdns_server will become PID 1 (in the container) and receive signals directly.
trap "/opt/pdns/bin/pdns_control --no-config quit" SIGHUP SIGINT SIGTERM

log "Starting PowerDNS server with arguments: ${cmd_args[*]} $@"
# Use 'exec' to replace the shell process with the pdns_server process
# This is the standard way to run the main application in a container
exec /opt/pdns/sbin/pdns_server "${cmd_args[@]}" "$@"

# The 'wait' from your original script is no longer needed because 'exec' 
# hands over process control entirely. If pdns_server exits, the container stops.