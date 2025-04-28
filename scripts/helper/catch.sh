#!/usr/bin/env bash
# Tool for catching STDOUT and STDERR into different variables
# Version: 1.0.0
#
# Dependencies:
#   None
#
# This script provides a function for running a command and catching STDOUT and STDERR into different variables
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# WARNING: This function MUST NEVER be changed!
#
# Executes a command and captures its STDOUT and STDERR into separate variables.
# The function handles multiline output and preserves the exact exit code.
#
# Arguments:
#   $1 - Name of variable to store stdout in
#   $2 - Name of variable to store stderr in
#   $3 - Command to execute
#   $4... - Arguments for the command
#
# Returns:
#   The exact exit code of the executed command
catch() {
    {
        IFS=$'\n' read -r -d '' "${1}"
        IFS=$'\n' read -r -d '' "${2}"
        (IFS=$'\n' read -r -d '' _ERRNO_; return "${_ERRNO_}")
    } < <((printf '\0%s\0%d\0' "$( ( ( ( { shift 2; "${@}"; echo "${?}" 1>&3-; } | tr -d '\0' 1>&4- ) 4>&2- 2>&1- | tr -d '\0' 1>&4- ) 3>&1- | exit "$(cat)" ) 4>&1- )" "${?}" 1>&2 ) 2>&1 )
}