#!/bin/bash
set -e

# Source shared database utilities
# shellcheck disable=SC1091
source /container/db_utils.sh

log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

# Check if required environment variables are defined
check_required_vars() {
    local required_vars=("$@")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log "Error: $var is not defined. Please set the required environment variables."
            exit 1
        fi
    done
}

check_backend_set() {
    if [ -n "$PDNS_GMYSQL_HOST" ] && [ -n "$PDNS_GPGSQL_HOST" ]; then
        log "Error: Both PDNS_GMYSQL_HOST and PDNS_GPGSQL_HOST are set. Please choose only one backend."
        exit 1
    elif [ -n "$PDNS_GMYSQL_HOST" ]; then
        log "MySQL backend detected. Running checks..."
        BACKEND_TYPE="mysql"
    elif [ -n "$PDNS_GPGSQL_HOST" ]; then
        log "PostgreSQL backend detected. Running checks..."
        BACKEND_TYPE="pgsql"
    else
        log "No database backend configured. Skipping database checks."
        BACKEND_TYPE="none"
    fi
}

wait_for_db() {
    local max_attempts=30
    local attempt=0
    local log_tag="Entrypoint"

    if [ "$BACKEND_TYPE" == "none" ]; then
        return 0 # No DB, nothing to wait for
    fi

    log "Checking ${BACKEND_TYPE} server availability..."

    while [ "$attempt" -lt "$max_attempts" ]; do
        # Use the shared, single-check function
        if check_db_connection "$log_tag"; then
            log "${BACKEND_TYPE} server is available."
            return 0
        else
            log "${BACKEND_TYPE} server is not yet available. Retrying in 5 seconds... (Attempt: $((attempt + 1)))"
            sleep 5
            ((attempt++))
        fi
    done

    log "Error: Unable to connect to ${BACKEND_TYPE} server after $max_attempts attempts. Exiting."
    exit 1
}

# --- MySQL Schema Sync ---
sync_mysql_schema() {
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

    # Check if database is empty first by checking for 'domains' table
    if ! mysql -h"$PDNS_GMYSQL_HOST" -P"$PDNS_GMYSQL_PORT" -u"$PDNS_GMYSQL_USER" -p"$PDNS_GMYSQL_PASSWORD" "$PDNS_GMYSQL_DBNAME" -e "SHOW TABLES LIKE 'domains';" | grep -q 'domains'; then
        log "No 'domains' table found. Database appears to be empty."
        log "Initializing database from $schema_file..."
        mysql -h"$PDNS_GMYSQL_HOST" -P"$PDNS_GMYSQL_PORT" -u"$PDNS_GMYSQL_USER" -p"$PDNS_GMYSQL_PASSWORD" "$PDNS_GMYSQL_DBNAME" < "$schema_file"
        log "MySQL schema successfully initialized."
        return
    fi

    log "Database is not empty. Checking for schema differences..."

    if ! mysqldump -h"$PDNS_GMYSQL_HOST" -P"$PDNS_GMYSQL_PORT" -u"$PDNS_GMYSQL_USER" -p"$PDNS_GMYSQL_PASSWORD" --no-data "$PDNS_GMYSQL_DBNAME" | diff - "$schema_file" > "$temp_diff_file"; then
        log "Detected differences in MySQL schema. Diff output:"
        cat "$temp_diff_file"
        
        # We only log the diff, but pt-table-sync logic is kept as requested
        log "Synchronizing using pt-table-sync... (WiP)"

        # Extract table names from schema.sql
        local tables
        tables=("$(grep -oP "(?<=CREATE TABLE \`)[^\`]+" "$schema_file")")

        # Synchronize each table
        for table in "${tables[@]}"; do
            log "Syncing table: $table"
            # WARNING: This command is high-risk. Ensure it does what you expect.
            # pt-table-sync --execute --verbose h="$PDNS_GMYSQL_HOST",P="$PDNS_GMYSQL_PORT",u="$PDNS_GMYSQL_USER",p="$PDNS_GMYSQL_PASSWORD" "$PDNS_GMYSQL_DBNAME"."$table" "$schema_file"
            log "Skipping pt-table-sync for $table as it's marked WiP."
        done
        log "Note: pt-table-sync logic is currently SKIPPED. Please review."

    else
        log "MySQL schema is already in sync with the local schema.sql file."
    fi

    rm -f "$temp_diff_file"
}

# --- PostgreSQL Schema Sync ---
sync_pgsql_schema() {
    local schema_file="/etc/pdns/pgsql_schema.sql"
    local temp_diff_file="/tmp/schema_diff.sql"
    local schema_name="pdns"

    # Verify PostgreSQL-related environment variables
    local pgsql_vars=(
        "PDNS_GPGSQL_HOST"
        "PDNS_GPGSQL_PORT"
        "PDNS_GPGSQL_USER"
        "PDNS_GPGSQL_PASSWORD"
        "PDNS_GPGSQL_DBNAME"
    )
    check_required_vars "${pgsql_vars[@]}"

    if [ ! -e "$schema_file" ]; then
        log "Error: PostgreSQL schema file $schema_file not found."
        exit 1
    fi

    log "Checking for existing PostgreSQL schema in database $PDNS_GPGSQL_DBNAME..."
    export PGPASSWORD="$PDNS_GPGSQL_PASSWORD"

    # Check if the target schema is empty or non-existent
    local table_count
    log "Checking table count in '$schema_name' schema..."
    table_count=$(psql -h "$PDNS_GPGSQL_HOST" -p "$PDNS_GPGSQL_PORT" -U "$PDNS_GPGSQL_USER" -d "$PDNS_GPGSQL_DBNAME" -t -c \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema = '$schema_name';" | tr -d '[:space:]')

    if [ "$?" -ne 0 ]; then
        log "Error: Failed to check table count. Does database '$PDNS_GPGSQL_DBNAME' exist?"
        unset PGPASSWORD
        exit 1
    fi

    if [ "$table_count" -eq 0 ]; then
        # Database is empty, initialize it
        log "No tables found in '$schema_name' schema. Database appears to be empty."
        log "Initializing database from $schema_file (forcing schema '$schema_name')..."
        
        (
            echo "CREATE SCHEMA IF NOT EXISTS \"$schema_name\";"
            echo "SET search_path = \"$schema_name\";"
            cat "$schema_file"
        ) | psql -h "$PDNS_GPGSQL_HOST" -p "$PDNS_GPGSQL_PORT" -U "$PDNS_GPGSQL_USER" -d "$PDNS_GPGSQL_DBNAME" -v ON_ERROR_STOP=1 --quiet

        if [ "$?" -ne 0 ]; then
            log "Error: Failed to initialize PostgreSQL schema."
            unset PGPASSWORD
            exit 1
        fi
        log "PostgreSQL schema successfully initialized."
    else
        # Database is not empty, check for diff
        log "Database is not empty ($table_count tables found in '$schema_name'). Checking for schema differences..."
        log "Comparing PostgreSQL schema '$schema_name' with local schema.sql file..."

        if ! pg_dump -h "$PDNS_GPGSQL_HOST" -p "$PDNS_GPGSQL_PORT" -U "$PDNS_GPGSQL_USER" -d "$PDNS_GPGSQL_DBNAME" --schema-only -n "$schema_name" --no-owner --no-privileges \
            | sed -e "s/$schema_name\.//g" \
                  -e '/^SET /d' \
                  -e '/^SELECT pg_catalog.set_config/d' \
                  -e '/^--/d' \
                  -e '/^CREATE SCHEMA/d' \
                  -e '/^ALTER SCHEMA/d' \
                  -e '/^$/d' \
            | diff -Bw - "$schema_file" > "$temp_diff_file"; then

            log "Detected differences in PostgreSQL schema '$schema_name'. Diff output:"
            cat "$temp_diff_file"
            log "Error: Schema mismatch. Please apply migrations manually."
            rm -f "$temp_diff_file"
            unset PGPASSWORD
            exit 1
        else
            log "PostgreSQL schema is already in sync with the local schema.sql file."
        fi
    fi

    rm -f "$temp_diff_file"
    unset PGPASSWORD
}

# --- Main Execution ---

# 1. Determine which backend (if any) is configured
check_backend_set

# 2. Wait for the database if one is configured
wait_for_db

# 3. Synchronize schema if a database is configured
if [ "$BACKEND_TYPE" == "mysql" ]; then
    sync_mysql_schema
elif [ "$BACKEND_TYPE" == "pgsql" ]; then
    sync_pgsql_schema
fi

cmd_args=()

# 4. Read all PDNS_ prefixed environment variables and convert them to command line parameters
while IFS='=' read -r name value; do
    if [[ $name == PDNS_* ]]; then
        cmd_args+=( "--$(tr '[:upper:]_' '[:lower:]-' <<< "${name#PDNS_}")=$value" )
    fi
done < <(env)

# 5. Start PowerDNS server
log "Starting PowerDNS server with arguments: ${cmd_args[*]}"

# setup traps for PowerDNS server
# Use exec to replace the shell with the pdns_server process
# This makes pdns_server PID 1 and allows it to receive signals correctly
exec /opt/pdns/sbin/pdns_server "${cmd_args[@]}" "$@"