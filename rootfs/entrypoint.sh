#!/bin/bash
set -e

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

# WiP
check_mysql_availability() {
    local max_attempts=30
    local attempt=0

    # Verify MySQL-related environment variables
    local mysql_vars=(
        "PDNS_GMYSQL_HOST"
        "PDNS_GMYSQL_PORT"
        "PDNS_GMYSQL_USER"
        "PDNS_GMYSQL_PASSWORD"
        "PDNS_GMYSQL_DBNAME"
    )

    check_required_vars "${mysql_vars[@]}"

    log "Checking MySQL server availability..."

    while [ "$attempt" -lt "$max_attempts" ]; do
        if mysqladmin ping -h"$PDNS_GMYSQL_HOST" -P"$PDNS_GMYSQL_PORT" -u"$PDNS_GMYSQL_USER" -p"$PDNS_GMYSQL_PASSWORD" &>/dev/null; then
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

    mysqldump -h"$PDNS_GMYSQL_HOST" -P"$PDNS_GMYSQL_PORT" -u"$PDNS_GMYSQL_USER" -p"$PDNS_GMYSQL_PASSWORD" --no-data "$PDNS_GMYSQL_DBNAME" | diff - "$schema_file" > "$temp_diff_file"

    if [ $? -eq 0 ]; then
        log "MySQL schema is already in sync with the local schema.sql file."
    else
        log "Detected differences in MySQL schema. Synchronizing using pt-table-sync..."

        # Extract table names from schema.sql
        tables=("$(grep -oP "(?<=CREATE TABLE \`)[^\`]+" "$schema_file")")

        # Synchronize each table
        for table in "${tables[@]}"; do
            pt-table-sync --execute --verbose h="$PDNS_GMYSQL_HOST",P="$PDNS_GMYSQL_PORT",u="$PDNS_GMYSQL_USER",p="$PDNS_GMYSQL_PASSWORD" "$PDNS_GMYSQL_DBNAME"."$table" "$schema_file"
        done
    fi

    rm -f "$temp_diff_file"
}

cmd_args=()

# Read all PDNS_ prefixed environment variables and convert them to command line parameters
while IFS='=' read -r name value; do
    if [[ $name == PDNS_* ]]; then
        cmd_args+=( "--$(tr '[:upper:]_' '[:lower:]-' <<< "${name#PDNS_}")=$value" )
    fi
done < <(env)

# setup traps for PowerDNS server
trap "/opt/pdns/bin/pdns_control --no-config quit" SIGHUP SIGINT SIGTERM

# Start PowerDNS with dynamically assembled command-line arguments
/opt/pdns/sbin/pdns_server "${cmd_args[@]}" "$@"

wait