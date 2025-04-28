#!/usr/bin/env bash
# Cluster clearing command for the cluster management tool
# Version: 1.0.0
#
# Dependencies:
#   - ansible.sh (for ansible_prepare, ansible_vault_password_option)
#   - log.sh (for logging functions)
#
# This script provides functions for clearing the cluster.
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# This function runs the clear playbook for the cluster.
# It asks for user confirmation and shows a countdown before execution.
clear_command() {
    local _response
    local _countdown=10
    local _countdown_line
    local _i

    # Ask for confirmation
    echo -e "${COLOR_RED_BOLD}WARNING: This will clear the entire cluster!${COLOR_RESET}"
    echo -e "Please type '${COLOR_WHITE_BOLD}Yes${COLOR_RESET}' to confirm: "
    read -r _response

    # Check response (case insensitive)
    if [[ "$(echo "$_response" | tr '[:upper:]' '[:lower:]')" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi

    # Show countdown
    echo -e "\n${COLOR_YELLOW_BOLD}Starting cluster clear in:${COLOR_RESET}"
    echo -ne "\r"
    for _i in $(seq 10 -1 1); do
        _countdown_line=""
        for _j in $(seq 10 -1 "${_i}"); do
            _countdown_line="${_countdown_line}${COLOR_YELLOW_BOLD}${_j}${COLOR_RESET}  "
        done
        echo -ne "\r${_countdown_line}"
        sleep 1
    done
    echo ""

    # Prepare and run playbook
    ansible_prepare

    # Run playbook
    ansible-playbook --vault-password-file "${VAULT_FILE}" --extra-vars @"${CLUSTER_FILE}" -i "${CLUSTER_FILE}" playbooks/clear.yml
}

# This function displays help information for the clear command.
clear_help() {
    echo "This command clears the entire cluster."
    echo "It will ask for confirmation before proceeding."
}

register_command "clear" "Clears the entire cluster" 