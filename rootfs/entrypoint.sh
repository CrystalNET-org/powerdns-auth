#!/bin/bash
set -e

log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

# Compile a list of environment variables prefixed with "PDNS_"
compile_pdns_variables() {
    local pdns_vars=()
    while IFS='=' read -r name _; do
        if [[ $name == PDNS_* ]]; then
            pdns_vars+=("$name")
        fi
    done < <(env)
    echo "${pdns_vars[@]}"
}

# Convert an environment variable name to a command-line parameter
env_var_to_cmd_arg() {
    local var_name="$1"
    local cmd_arg

    cmd_arg="--$(echo "${var_name#PDNS_}" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')"
    echo "$cmd_arg"
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

# Assemble PowerDNS arguments dynamically
assemble_pdns_arguments() {
    local cmd_arg
    local pdns_vars
    local arguments=()

    pdns_vars=("$(compile_pdns_variables)")
    for var in "${pdns_vars[@]}"; do
        cmd_arg=$(env_var_to_cmd_arg "$var")
        arguments+=( "$cmd_arg=${!var}" )
    done

    echo "${arguments[@]}"
}

# setup traps for PowerDNS server
trap "pdns_control quit" SIGHUP SIGINT SIGTERM

# Start PowerDNS with dynamically assembled command-line arguments
/usr/sbin/pdns_server "$(assemble_pdns_arguments)" "$@"

wait