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
    local temp_diff_file="/tmp/schema_diff.sql" # Keep for now, in case you reuse it

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

    log "Checking MySQL schema in database $PDNS_GMYSQL_DBNAME..."

    # Check if database is empty first by checking for 'domains' table
    if ! mysql -h"$PDNS_GMYSQL_HOST" -P"$PDNS_GMYSQL_PORT" -u"$PDNS_GMYSQL_USER" -p"$PDNS_GMYSQL_PASSWORD" "$PDNS_GMYSQL_DBNAME" -e "SHOW TABLES LIKE 'domains';" | grep -q 'domains'; then
        log "No 'domains' table found. Database appears to be empty."
        log "Initializing database from $schema_file..."
        mysql -h"$PDNS_GMYSQL_HOST" -P"$PDNS_GMYSQL_PORT" -u"$PDNS_GMYSQL_USER" -p"$PDNS_GMYSQL_PASSWORD" "$PDNS_GMYSQL_DBNAME" < "$schema_file"
        log "MySQL schema successfully initialized."
        return
    fi

    # --- NOTE: 'diff' check is too unreliable ---
    # We could implement a similar hash check here as for PostgreSQL
    # by querying 'information_schema.columns'.
    log "Database is not empty. Assuming schema is compatible. (MySQL hash check not yet implemented)"

    rm -f "$temp_diff_file"
}

# --- PostgreSQL Schema Sync ---
sync_pgsql_schema() {
    local schema_file="/etc/pdns/pgsql_schema.sql"
    local schema_name="pdns"
    local temp_schema_name="pdns_upstream_check" # NEW: Temporary schema name
    
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
        # Database is empty, initialize it (LOGIC UNCHANGED)
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
        # --- NEW LOGIC: In-DB Schema Comparison ---
        log "Database is not empty ($table_count tables found). Comparing live schema to upstream schema via temp schema..."

        # 1. Clean up if exists
        log "Cleaning up old temp schema (if any)..."
        psql -h "$PDNS_GPGSQL_HOST" -p "$PDNS_GPGSQL_PORT" -U "$PDNS_GPGSQL_USER" -d "$PDNS_GPGSQL_DBNAME" -c "DROP SCHEMA IF EXISTS \"$temp_schema_name\" CASCADE;" --quiet

        # 2. Load upstream schema into temporary schema
        log "Loading upstream schema into '$temp_schema_name' for comparison..."
        (
            echo "CREATE SCHEMA IF NOT EXISTS \"$temp_schema_name\";"
            echo "SET search_path = \"$temp_schema_name\";"
            cat "$schema_file"
        ) | psql -h "$PDNS_GPGSQL_HOST" -p "$PDNS_GPGSQL_PORT" -U "$PDNS_GPGSQL_USER" -d "$PDNS_GPGSQL_DBNAME" -v ON_ERROR_STOP=1 --quiet
        
        if [ "$?" -ne 0 ]; then
            log "Error: Failed to load upstream schema into temp schema '$temp_schema_name'."
            psql -h "$PDNS_GPGSQL_HOST" -p "$PDNS_GPGSQL_PORT" -U "$PDNS_GPGSQL_USER" -d "$PDNS_GPGSQL_DBNAME" -c "DROP SCHEMA IF EXISTS \"$temp_schema_name\" CASCADE;" --quiet # Cleanup
            unset PGPASSWORD
            exit 1
        fi

        # 3. Get "golden" fingerprint (from temp schema)
        local golden_fingerprint
        golden_fingerprint=$(psql -h "$PDNS_GPGSQL_HOST" -p "$PDNS_GPGSQL_PORT" -U "$PDNS_GPGSQL_USER" -d "$PDNS_GPGSQL_DBNAME" -t -c \
            "SELECT table_name || '.' || column_name FROM information_schema.columns WHERE table_schema = '$temp_schema_name' ORDER BY 1;" \
            | tr -d '[:space:]' | sed '/^$/d') # remove whitespace and empty lines

        # 4. Get "live" fingerprint (from 'pdns' schema)
        local live_fingerprint
        live_fingerprint=$(psql -h "$PDNS_GPGSQL_HOST" -p "$PDNS_GPGSQL_PORT" -U "$PDNS_GPGSQL_USER" -d "$PDNS_GPGSQL_DBNAME" -t -c \
            "SELECT table_name || '.' || column_name FROM information_schema.columns WHERE table_schema = '$schema_name' ORDER BY 1;" \
            | tr -d '[:space:]' | sed '/^$/d') # remove whitespace and empty lines

        # 5. Clean up temporary schema (now that we have the fingerprints)
        log "Dropping temporary schema '$temp_schema_name'..."
        psql -h "$PDNS_GPGSQL_HOST" -p "$PDNS_GPGSQL_PORT" -U "$PDNS_GPGSQL_USER" -d "$PDNS_GPGSQL_DBNAME" -c "DROP SCHEMA IF EXISTS \"$temp_schema_name\" CASCADE;" --quiet

        # 6. Compare and show differences
        local schema_diff
        # `diff -U 0` shows only differences. `tail` removes the header.
        # We compare "golden" (expected) vs "live" (actual)
        schema_diff=$(diff -U 0 <(echo "$golden_fingerprint") <(echo "$live_fingerprint") | tail -n +3)

        if [ -n "$schema_diff" ]; then
            log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            log "ERROR: Schema structure mismatch!"
            log "Differences ( '-' = missing from DB / '+' = extra in DB ):"
            # Remove leading whitespace from diff output
            echo "$schema_diff" | sed 's/^[[:space:]]*//'
            log "This indicates an incompatible schema version. Please migrate the database manually."
            log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            unset PGPASSWORD
            exit 1
        else
            log "Schema structure is in sync. Assuming schema is compatible."
        fi
        # --- END OF NEW LOGIC ---
    fi

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