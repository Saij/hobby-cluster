#!/usr/bin/env bash
# Dependency checking functions for the cluster management tool
# Version: 1.0.0
#
# Dependencies:
#   - log.sh (for logging functions)
#
# This script provides functions for checking command dependencies.
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# This function checks if a command is available in the system PATH.
#
# Arguments:
#   $1 - Command name to check
check_command() {
    local _command="$1"
    
    if ! command -v "$_command" >/dev/null 2>&1; then
        log_error "Required command '$_command' not found in PATH"
        exit 1
    fi
}