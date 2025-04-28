#!/usr/bin/env bash
# Usage helper functions for the cluster management tool
# Version: 1.0.0
#
# Dependencies:
#   - log.sh (for logging functions)
#
# This script provides functions for displaying help and usage information
# for the cluster management tool. 
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# This function displays common options for all commands.
usage_options() {
    printf '%s\n' \
        "Options:" \
        "  -c, --cluster <cluster>   Which cluster configuration to use (required)" \
        "  -v, --verbose             Enable verbose output" \
        "      --reinstall           Force reinstallation of dependencies" \
        "  -h, --help                Display this help message"
}

# This function displays the usage header with command-specific information.
#
# Arguments:
#   $1 - Optional command name to display specific help for
usage_header() {
    local _command="${1:-}"
    local _script_name
    _script_name="$(basename "$0")"
    
    printf '%s\n' \
        "Usage: $_script_name ${_command:-[COMMAND]} [-h] [-v] -c <cluster> [COMMAND OPTIONS] [ARGUMENTS]" \
        "" \
        "Hobby cluster management tool" \
        ""

    if [[ -n "$_command" ]]; then
        local _desc_var="COMMANDS_DESC__$_command"
        if [[ -z "${!_desc_var:-}" ]]; then
            log_error "No description found for command '$_command'"
            exit 1
        fi
        local _desc="${!_desc_var}"
  
        printf '%s\n' "Command: $_command"
        printf '%s\n' "$_desc"
        printf '%s\n' ""
    fi
}

# This function displays comprehensive help information.
#
# Arguments:
#   $1 - Optional command name to display specific help for
usage() {
    local _command="${1:-}"
    
    usage_header "$_command"    
    usage_options

    if [[ -n "$_command" ]]; then
        local _help_func="COMMANDS_HELP_FUNC__$_command"
        if declare -F "${!_help_func:-}" > /dev/null; then
            printf '%s\n' ""
            "${!_help_func}"
        fi
    else
        # List all commands
        printf '%s\n' ""
        printf '%s\n' "Commands:"

        for i in "${!COMMANDS[@]}"; do
            local _command="${COMMANDS[$i]}"
            local _desc_var="COMMANDS_DESC__${_command}"
            if [[ -z "${!_desc_var:-}" ]]; then
                log_warn "No description found for command '$_command'"
                continue
            fi
            local _desc="${!_desc_var}"

            printf '  %-17s %s\n' "$_command" "$_desc"
        done
    fi
}