#!/usr/bin/env bash
# Array manipulation functions for the cluster management tool
# Version: 1.0.0
#
# Dependencies:
#   None
#
# This script provides functions for manipulating arrays in shell scripts.
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# This function joins array elements with a delimiter.
# Outputs the joined string to stdout
#
# Arguments:
#   $1 - Array name (passed by reference)
#   $2 - Delimiter

array_join() {
    local _array_name="$1"
    local _delimiter="$2"
    local _result=""
    local _first=true
    local _element

    # Create a local reference to the array
    eval "local -a _array_ref=(\"\${${_array_name}[@]}\")"

    # Join elements
    # shellcheck disable=SC2154
    for _element in "${_array_ref[@]}"; do
        if $_first; then
            _result="$_element"
            _first=false
        else
            _result="$_result$_delimiter$_element"
        fi
    done

    # Output the result
    echo "$_result"
    return 0
}