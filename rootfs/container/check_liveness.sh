#!/bin/bash
#
# This script performs a LIVENESS check for the PowerDNS container.
# It checks if the main 'pdns_server' process is running.
# This check is intentionally lightweight.
#
# It exits with 0 if the process is found, 1 otherwise.
set -e

log_msg="[Liveness] - $(date +"%Y-%m-%d %H:%M:%S")"

# Use pgrep -x to match the exact process name "pdns_server"
if pgrep -x "pdns_server" > /dev/null; then
    echo "$log_msg - pdns_server process is running."
    exit 0
else
    echo "$log_msg - pdns_server process NOT found."
    exit 1
fi