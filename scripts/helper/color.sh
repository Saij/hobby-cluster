#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# Terminal color utilities for the cluster management tool
# Version: 1.0.0
#
# Dependencies:
#   None
#
# This script provides functions for colored terminal output.
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# This function checks if the terminal supports colors.
#
# Returns:
#   0 - Terminal supports colors
#   1 - Terminal does not support colors
has_colors() {
    # Check if we're running in a terminal
    if [[ ! -t 1 ]]; then
        return 1
    fi

    # Check for dumb terminal
    local _term="${TERM:-dumb}"
    if [[ "$_term" == "dumb" ]]; then
        return 1
    fi

    # Check for color support using tput
    if command -v tput > /dev/null 2>&1; then
        if [[ $(tput -T"${_term}" colors) -ge 8 ]]; then
            return 0
        fi
    fi

    # Check for common environment variables that indicate color support
    if [[ -n "$COLORTERM" || "$CLICOLOR" == "1" || "$CLICOLOR_FORCE" == "1" ]]; then
        return 0
    fi

    return 1
}

# Initialize color variables based on terminal support
if has_colors; then
    # Text formatting
    COLOR_RESET="\033[0m"
    COLOR_BOLD="\033[1m"
    COLOR_DIM="\033[2m"
    COLOR_ITALIC="\033[3m"
    COLOR_UNDERLINE="\033[4m"
    COLOR_BLINK="\033[5m"
    COLOR_REVERSE="\033[7m"
    COLOR_HIDDEN="\033[8m"
    COLOR_STRIKETHROUGH="\033[9m"

    # Standard colors
    COLOR_BLACK="\033[0;30m"
    COLOR_RED="\033[0;31m"
    COLOR_GREEN="\033[0;32m"
    COLOR_YELLOW="\033[0;33m"
    COLOR_BLUE="\033[0;34m"
    COLOR_MAGENTA="\033[0;35m"
    COLOR_CYAN="\033[0;36m"
    COLOR_WHITE="\033[0;37m"

    # Bright colors
    COLOR_BRIGHT_BLACK="\033[0;90m"
    COLOR_BRIGHT_RED="\033[0;91m"
    COLOR_BRIGHT_GREEN="\033[0;92m"
    COLOR_BRIGHT_YELLOW="\033[0;93m"
    COLOR_BRIGHT_BLUE="\033[0;94m"
    COLOR_BRIGHT_MAGENTA="\033[0;95m"
    COLOR_BRIGHT_CYAN="\033[0;96m"
    COLOR_BRIGHT_WHITE="\033[0;97m"

    # Background colors
    COLOR_BG_BLACK="\033[40m"
    COLOR_BG_RED="\033[41m"
    COLOR_BG_GREEN="\033[42m"
    COLOR_BG_YELLOW="\033[43m"
    COLOR_BG_BLUE="\033[44m"
    COLOR_BG_MAGENTA="\033[45m"
    COLOR_BG_CYAN="\033[46m"
    COLOR_BG_WHITE="\033[47m"

    # Bright background colors
    COLOR_BG_BRIGHT_BLACK="\033[100m"
    COLOR_BG_BRIGHT_RED="\033[101m"
    COLOR_BG_BRIGHT_GREEN="\033[102m"
    COLOR_BG_BRIGHT_YELLOW="\033[103m"
    COLOR_BG_BRIGHT_BLUE="\033[104m"
    COLOR_BG_BRIGHT_MAGENTA="\033[105m"
    COLOR_BG_BRIGHT_CYAN="\033[106m"
    COLOR_BG_BRIGHT_WHITE="\033[107m"

    # Common combinations
    COLOR_WHITE_BOLD="${COLOR_WHITE}${COLOR_BOLD}"
    COLOR_WHITE_ITALIC="${COLOR_WHITE}${COLOR_ITALIC}"
    COLOR_WHITE_UNDERLINE="${COLOR_WHITE}${COLOR_UNDERLINE}"
    
    COLOR_RED_BOLD="${COLOR_RED}${COLOR_BOLD}"
    COLOR_RED_ITALIC="${COLOR_RED}${COLOR_ITALIC}"
    COLOR_RED_UNDERLINE="${COLOR_RED}${COLOR_UNDERLINE}"
    
    COLOR_GREEN_BOLD="${COLOR_GREEN}${COLOR_BOLD}"
    COLOR_GREEN_ITALIC="${COLOR_GREEN}${COLOR_ITALIC}"
    COLOR_GREEN_UNDERLINE="${COLOR_GREEN}${COLOR_UNDERLINE}"
    
    COLOR_YELLOW_BOLD="${COLOR_YELLOW}${COLOR_BOLD}"
    COLOR_YELLOW_ITALIC="${COLOR_YELLOW}${COLOR_ITALIC}"
    COLOR_YELLOW_UNDERLINE="${COLOR_YELLOW}${COLOR_UNDERLINE}"
    
    COLOR_BLUE_BOLD="${COLOR_BLUE}${COLOR_BOLD}"
    COLOR_BLUE_ITALIC="${COLOR_BLUE}${COLOR_ITALIC}"
    COLOR_BLUE_UNDERLINE="${COLOR_BLUE}${COLOR_UNDERLINE}"
    
    COLOR_MAGENTA_BOLD="${COLOR_MAGENTA}${COLOR_BOLD}"
    COLOR_MAGENTA_ITALIC="${COLOR_MAGENTA}${COLOR_ITALIC}"
    COLOR_MAGENTA_UNDERLINE="${COLOR_MAGENTA}${COLOR_UNDERLINE}"
    
    COLOR_CYAN_BOLD="${COLOR_CYAN}${COLOR_BOLD}"
    COLOR_CYAN_ITALIC="${COLOR_CYAN}${COLOR_ITALIC}"
    COLOR_CYAN_UNDERLINE="${COLOR_CYAN}${COLOR_UNDERLINE}"
    
    # Bright color combinations
    COLOR_BRIGHT_WHITE_BOLD="${COLOR_BRIGHT_WHITE}${COLOR_BOLD}"
    COLOR_BRIGHT_RED_BOLD="${COLOR_BRIGHT_RED}${COLOR_BOLD}"
    COLOR_BRIGHT_GREEN_BOLD="${COLOR_BRIGHT_GREEN}${COLOR_BOLD}"
    COLOR_BRIGHT_YELLOW_BOLD="${COLOR_BRIGHT_YELLOW}${COLOR_BOLD}"
    COLOR_BRIGHT_BLUE_BOLD="${COLOR_BRIGHT_BLUE}${COLOR_BOLD}"
    COLOR_BRIGHT_MAGENTA_BOLD="${COLOR_BRIGHT_MAGENTA}${COLOR_BOLD}"
    COLOR_BRIGHT_CYAN_BOLD="${COLOR_BRIGHT_CYAN}${COLOR_BOLD}"
    
    # Special combinations for common use cases
    COLOR_ERROR="${COLOR_RED_BOLD}"
    COLOR_WARNING="${COLOR_YELLOW_BOLD}"
    COLOR_SUCCESS="${COLOR_GREEN_BOLD}"
    COLOR_INFO="${COLOR_BLUE_BOLD}"
    COLOR_DEBUG="${COLOR_CYAN_ITALIC}"
    COLOR_HIGHLIGHT="${COLOR_WHITE_BOLD}"
    COLOR_DIM_TEXT="${COLOR_DIM}${COLOR_WHITE}"
else
    # Set all color variables to empty strings if terminal doesn't support colors
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_DIM=""
    COLOR_ITALIC=""
    COLOR_UNDERLINE=""
    COLOR_BLINK=""
    COLOR_REVERSE=""
    COLOR_HIDDEN=""
    COLOR_STRIKETHROUGH=""

    COLOR_BLACK=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_MAGENTA=""
    COLOR_CYAN=""
    COLOR_WHITE=""

    COLOR_BRIGHT_BLACK=""
    COLOR_BRIGHT_RED=""
    COLOR_BRIGHT_GREEN=""
    COLOR_BRIGHT_YELLOW=""
    COLOR_BRIGHT_BLUE=""
    COLOR_BRIGHT_MAGENTA=""
    COLOR_BRIGHT_CYAN=""
    COLOR_BRIGHT_WHITE=""

    COLOR_BG_BLACK=""
    COLOR_BG_RED=""
    COLOR_BG_GREEN=""
    COLOR_BG_YELLOW=""
    COLOR_BG_BLUE=""
    COLOR_BG_MAGENTA=""
    COLOR_BG_CYAN=""
    COLOR_BG_WHITE=""

    COLOR_BG_BRIGHT_BLACK=""
    COLOR_BG_BRIGHT_RED=""
    COLOR_BG_BRIGHT_GREEN=""
    COLOR_BG_BRIGHT_YELLOW=""
    COLOR_BG_BRIGHT_BLUE=""
    COLOR_BG_BRIGHT_MAGENTA=""
    COLOR_BG_BRIGHT_CYAN=""
    COLOR_BG_BRIGHT_WHITE=""

    # Common combinations
    COLOR_WHITE_BOLD=""
    COLOR_WHITE_ITALIC=""
    COLOR_WHITE_UNDERLINE=""
    
    COLOR_RED_BOLD=""
    COLOR_RED_ITALIC=""
    COLOR_RED_UNDERLINE=""
    
    COLOR_GREEN_BOLD=""
    COLOR_GREEN_ITALIC=""
    COLOR_GREEN_UNDERLINE=""
    
    COLOR_YELLOW_BOLD=""
    COLOR_YELLOW_ITALIC=""
    COLOR_YELLOW_UNDERLINE=""
    
    COLOR_BLUE_BOLD=""
    COLOR_BLUE_ITALIC=""
    COLOR_BLUE_UNDERLINE=""
    
    COLOR_MAGENTA_BOLD=""
    COLOR_MAGENTA_ITALIC=""
    COLOR_MAGENTA_UNDERLINE=""
    
    COLOR_CYAN_BOLD=""
    COLOR_CYAN_ITALIC=""
    COLOR_CYAN_UNDERLINE=""
    
    # Bright color combinations
    COLOR_BRIGHT_WHITE_BOLD=""
    COLOR_BRIGHT_RED_BOLD=""
    COLOR_BRIGHT_GREEN_BOLD=""
    COLOR_BRIGHT_YELLOW_BOLD=""
    COLOR_BRIGHT_BLUE_BOLD=""
    COLOR_BRIGHT_MAGENTA_BOLD=""
    COLOR_BRIGHT_CYAN_BOLD=""
    
    # Special combinations for common use cases
    COLOR_ERROR=""
    COLOR_WARNING=""
    COLOR_SUCCESS=""
    COLOR_INFO=""
    COLOR_DEBUG=""
    COLOR_HIGHLIGHT=""
    COLOR_DIM_TEXT=""
fi