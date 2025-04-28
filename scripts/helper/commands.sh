#!/usr/bin/env bash
# Command registration functions for the cluster management tool
# Version: 1.0.0
#
# Dependencies:
#   None
#
# This script provides functions for registering and managing commands.
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Register a new command
# This function registers a command with its description and associated functions.
#
# Arguments:
#   $1 - Command name
#   $2 - Command description
register_command() {
    local _command="$1"
    local _desc="$2"

    COMMANDS+=( "$_command" )
    printf -v "COMMANDS_RUN_FUNC__${_command}" %s "${_command}_command"
    printf -v "COMMANDS_HELP_FUNC__${_command}" %s "${_command}_help"
    printf -v "COMMANDS_OPTIONS_FUNC__${_command}" %s "${_command}_options"
    printf -v "COMMANDS_DESC__${_command}" %s "$_desc"
} 