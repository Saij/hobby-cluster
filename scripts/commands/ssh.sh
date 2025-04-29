#!/usr/bin/env bash
# SSH command for the cluster management tool
# Version: 1.0.0
#
# Dependencies:
#   - ansible.sh (for inventory helpers)
#   - log.sh (for logging functions)
#   - catch.sh (for output catching)
#   - usage.sh (for usage/help output)
#
# This script provides the ssh command, allowing SSH access to a node by name,
# using the cluster inventory to resolve the IP address. 
# It should be sourced
# by the main script and not executed directly.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Global variable for the node name
SSH_NODE_NAME=

# This function handles the ssh command.
# It connects to a node by name, resolving the IP from the inventory and using SSH.
ssh_command() {
    if [[ -z "$SSH_NODE_NAME" ]]; then
        log_error "No node name provided."
        usage "ssh"
        exit 1
    fi

    # Prepare inventory
    ansible_prepare

    local _inv_out _inv_err
    catch "_inv_out" "_inv_err" ansible-inventory --vault-password-file "${VAULT_FILE}" --list --export -i "${CLUSTER_FILE}"
    if [[ -n "$_inv_err" ]]; then
        log_error "Error loading inventory!"
        
        local _result
        # Extract the block: after "with cluster plugin:" and up to but not including the next [WARNING]
        _result=$(echo "$_inv_err" | tr '\n' ' ' | sed -E 's/.*with cluster plugin:[[:space:]]*([^[]*)\[WARNING\].*/\1/')

        # Trim leading and trailing spaces
        _result=$(echo "$_result" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

        if [[ -n "$_result" ]]; then
            log_error "Cluster plugin error: ${_result}"
        else
            log_error "Unknown error:"
            log_error "$_inv_err"
        fi

        exit 1
    fi

    if [ -z "$_inv_out" ]; then
        log_error "Inventory is empty"
        exit 1
    fi
    if ! echo "$_inv_out" | jq empty >/dev/null 2>&1; then
        log_error "Invalid inventory format"
        exit 1
    fi

    # Get the node's IP address
    local _ip
    _ip=$(ansible_get_host_var "$_inv_out" "$SSH_NODE_NAME" "ansible_host")
    if [[ -z "$_ip" || "$_ip" == "null" ]]; then
        log_error "Node '$SSH_NODE_NAME' not found or does not have an IP address (not yet created?)"
        exit 1
    fi

    log_info "Connecting to $SSH_NODE_NAME ($_ip)..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$_ip"
}

# This function processes command line options for the ssh command.
#
# Arguments:
#   All command line arguments
ssh_options() {
    local i=1
    SSH_NODE_NAME=

    # Process all arguments
    while [ $i -le $# ]; do
        eval "ARG=\${$i}"
        case "$ARG" in
            -*)
                log_error "Invalid option: $ARG"
                usage "ssh"
                exit 1
                ;;
            *)
                if [[ -z "$SSH_NODE_NAME" ]]; then
                    SSH_NODE_NAME="$ARG"
                else
                    log_error "Only one host allowed"
                    usage "ssh"
                    exit 1
                fi
                ;;
        esac
        i=$((i + 1))
    done

}
# This function displays help information for the ssh command.
ssh_help() {
    echo "Command arguments:"
    echo "  <node>               Shows details for node <node>"
}

register_command "ssh" "SSH into a node by name using inventory" 