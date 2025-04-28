#!/usr/bin/env bash
# Deploys the cluster. Provisions servers, configures base system and installs Kubernetes.
# Version: 1.0.0
#
# Dependencies:
#   - ansible.sh (for ansible_prepare, ansible_vault_password_option)
#   - log.sh (for logging functions)
#
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Global variables
PLAY_DEBUG=false
PLAY_CHECK=false

# This function runs the Ansible playbook for the cluster.
play_command() {
    # Initialize the args array
    local -a _args=("-i" "${CLUSTER_FILE}" "--extra-vars" "@${CLUSTER_FILE}" "--vault-password-file" "${VAULT_FILE}")

    # Prepare Ansible environment
    ansible_prepare

    # Add debug flag if enabled
    if $PLAY_DEBUG; then
        _args+=("-vvv")
    fi

    # Add check flag if enabled
    if $PLAY_CHECK; then
        _args+=("--check")
    fi

    # Run playbook
    ansible-playbook "${_args[@]}" playbooks/cluster.yml
}

# This function displays help information for the play command.
play_help() {
    echo "Command Options:"
    echo "  -d, --debug         Enable debug output"
    echo "  -C, --check         Run ansible check"
}

# This function processes command line options for the play command.
#
# Arguments:
#   All command line arguments
play_options() {
    local i=1

    # Process all arguments
    while [ $i -le $# ]; do
        eval "ARG=\${$i}"
        case "$ARG" in
            -d|--debug)
                PLAY_DEBUG=true
                ;;
            -C|--check)
                PLAY_CHECK=true
                ;;
            -*)
                log_error "Invalid option: $ARG"
                usage "play"
                exit 1
                ;;
        esac
        i=$((i + 1))
    done
}

register_command "play" "Runs ansible playbooks"