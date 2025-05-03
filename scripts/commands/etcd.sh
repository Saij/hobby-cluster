#!/usr/bin/env bash
# Etcd command for the cluster management tool
# Version: 1.0.0
#
# Dependencies:
#   - ansible.sh (for ansible_prepare)
#   - log.sh (for logging functions)
#   - catch.sh (for error catching)
#
# This script provides functions for displaying etcd status in the cluster.
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

ETCD_WATCH=false

# This function displays help information for the etcd command.
etcd_help() {
    echo "Command Options:"
    echo "  -w, --watch               Reprints etcd status every second"
}

# This function processes command line options for the etcd command.
etcd_options() {
    local i=1

    # Process all arguments
    while [ $i -le $# ]; do
        eval "ARG=\${$i}"
        case "$ARG" in
            -w|--watch)
                ETCD_WATCH=true
                ;;
            -*)
                log_error "Invalid option: $ARG"
                usage "etcd"
                exit 1
                ;;
        esac
        i=$((i + 1))
    done
}

# This function handles the etcd command.
# It displays information about the etcd status.
etcd_command() {
    local _inv_out
    local _inv_err

    # Prepare Ansible environment
    ansible_prepare

    # Load inventory
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

    # Check if inventory is empty
    if [ -z "$_inv_out" ]; then
        log_error "Inventory is empty"
        return 1
    fi

    # Check if inventory is valid JSON
    if ! echo "$_inv_out" | jq empty >/dev/null 2>&1; then
        log_error "Invalid inventory format"
        return 1
    fi

    log_debug "Inventory JSON"
    log_debug "$_inv_out"

    echo ""

    local _ip
    local _control_hosts
    _control_hosts=$(echo "$_inv_out" | jq -r '._control.hosts[]?')

    for _host in $_control_hosts; do
        _ip=$(ansible_get_host_var "$_inv_out" "$_host" "ansible_host")

        if [[ -n "$_ip" && "$_ip" != "null" ]]; then
            break
        fi
    done

    if [[ -z "$_ip" || "$_ip" == "null" ]]; then
        log_error "No control node with a valid IP address found (are the nodes not yet created?)"
        exit 1
    fi

    local _etcd_commands=()
    _etcd_commands+=("/opt/etcd/etcdctl endpoint status --cluster --write-out table")
    _etcd_commands+=("/opt/etcd/etcdctl endpoint health --cluster --write-out table")

    # Construct remote command
    local _remote_cmd=""
    for cmd in "${_etcd_commands[@]}"; do
        # Escape each command properly for remote execution
        _remote_cmd+="$cmd; "
    done

    # Remove trailing semicolon and space
    _remote_cmd=${_remote_cmd%; }

    # Wrap in 'watch' if ETCD_WATCH is true
    if [[ "$ETCD_WATCH" == true ]]; then
        _remote_cmd="watch -t -c -n 1 \"$_remote_cmd\""
    fi

    # Execute via SSH
    ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$_ip" "$_remote_cmd"
}

register_command "etcd" "Shows etcd status"