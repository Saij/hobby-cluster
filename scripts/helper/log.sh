#!/usr/bin/env bash
# Logging utilities for the cluster management tool
# Version: 1.0.0
#
# Dependencies:
#   - color.sh (for color support)
#
# This script provides functions for logging with different severity levels
# and color support. 
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# This function logs a message with a specific channel and color.
#
# Arguments:
#   $1 - Channel name (e.g., "INFO", "ERROR")
#   $2 - Color code (from color.sh)
#   $3 - Message to log
log() {
    # Check number of arguments
    if [[ $# -ne 3 ]]; then
        log_error "log: Invalid number of arguments (expected 3, got $#)"
        exit 1
    fi

    local _channel_name="$1"
    local _color_code="$2"
    local _message="$3"

    # Validate arguments
    if [[ -z "$_channel_name" ]]; then
        log_error "log: Channel name is required"
        exit 1
    fi

    if [[ -z "$_message" ]]; then
        log_error "log: Message is required"
        exit 1
    fi

    # Log the message with color if supported
    echo -e "${_color_code}[${_channel_name}]${COLOR_RESET} ${_message}"
}

# This function logs a debug message (only shown in verbose mode).
#
# Arguments:
#   $1 - Message to log
log_debug() {
    if $VERBOSE; then
        log "DEBUG" "$COLOR_DEBUG" "$1"
    fi
}

# This function logs an info message.
#
# Arguments:
#   $1 - Message to log
log_info() {
    log "INFO" "$COLOR_INFO" "$1"
}

# This function logs a warning message.
#
# Arguments:
#   $1 - Message to log
log_warn() {
    log "WARNING" "$COLOR_WARNING" "$1"
}

# This function logs an error message.
#
# Arguments:
#   $1 - Message to log
log_error() {
    log "ERROR" "$COLOR_ERROR" "$1"
}