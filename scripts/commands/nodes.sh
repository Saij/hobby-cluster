#!/usr/bin/env bash
# Node display command for the cluster management tool
# Version: 1.0.0
#
# Dependencies:
#   - ansible.sh (for ansible_prepare, ansible_vault_password_option)
#   - log.sh (for logging functions)
#   - catch.sh (for error catching)
#   - array.sh (for array_join)
#
# This script provides functions for displaying nodes in the cluster.
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Global variables
NODES_SINGLE_NODE=

# This function handles the nodes command.
# It displays information about nodes in the inventory.
nodes_command() {
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

    echo ""

    # Show all nodes or specific node
    if [ -z "$NODES_SINGLE_NODE" ]; then
        nodes_show_all "$_inv_out"
    else
        nodes_show_single "$_inv_out" "$NODES_SINGLE_NODE"
    fi
}

# This function displays help information for the nodes command.
nodes_help() {
    echo "Command Options:"
    echo "  -n, --node <node>    Shows details for node <node>"
}

# This function processes command line options for the nodes command.
nodes_options() {
    local i=1

    # Process all arguments
    while [ $i -le $# ]; do
        eval "ARG=\${$i}"
        case "$ARG" in
            -n|--node)
                i=$((i + 1))
                eval "NODES_SINGLE_NODE=\${$i}"
                if [[ -z "$NODES_SINGLE_NODE" ]]; then
                    log_error "Option $ARG requires an argument"
                    usage "nodes"
                    exit 1
                fi
                ;;
            --node=*)
                NODES_SINGLE_NODE="${ARG#*=}"
                if [[ -z "$NODES_SINGLE_NODE" ]]; then
                    log_error "Option --node requires an argument"
                    usage "nodes"
                    exit 1
                fi
                ;;
            -*)
                log_error "Invalid option: $ARG"
                usage "nodes"
                exit 1
                ;;
        esac
        i=$((i + 1))
    done
}

# This function checks if a group should be displayed.
# We skip special groups that are used internally by Ansible or our cluster plugin:
# - _meta: Contains host variables
# - all: Default group containing all hosts
# - unmanaged: Hosts that should be deleted
# - controlplane/worker: Role-based groups
# - managed: All managed hosts
#
# Arguments:
#   $1 - Group name to check
#
# Returns:
#   0 - Group should be displayed
#   1 - Group should be skipped
nodes_should_skip_group() {
    [[ "$1" == "_meta" || "$1" == "all" || "$1" == "unmanaged" || "$1" == "controlplane" || "$1" == "worker" || "$1" == "managed" ]]
}

# This function displays information about all nodes in the inventory.
# It shows group information, server types, and host details.
#
# Arguments:
#   $1 - Inventory output
nodes_show_all() {
    local _inv_out="$1"
    local _group
    local _is_control
    local _is_worker
    local _server_type
    local _image
    local -a _group_functions=()
    local _host
    local _needs_create
    local _location
    local _host_asterisk
    local _ip

    for _group in $(echo "$_inv_out" | jq -r ". | keys | .[]"); do
        if nodes_should_skip_group "$_group"; then
            continue
        fi

        _is_control=$(ansible_get_group_var "$_inv_out" "$_group" "is_control")
        _is_worker=$(ansible_get_group_var "$_inv_out" "$_group" "is_worker")
        _server_type=$(ansible_get_group_var "$_inv_out" "$_group" "type")
        _image=$(ansible_get_group_var "$_inv_out" "$_group" "image")

        _group_functions=()
        if $_is_control; then
            _group_functions+=("Control-Plane")
        fi
        if $_is_worker; then
            _group_functions+=("Worker")
        fi

        echo -e "${COLOR_WHITE_BOLD}$_group ($(array_join _group_functions ", "))${COLOR_RESET}"

        echo -e "  Server-Type: ${COLOR_WHITE_BOLD}$_server_type${COLOR_RESET}"
        echo -e "  OS Image: ${COLOR_WHITE_BOLD}$_image${COLOR_RESET}"
        echo "  Hosts:"

        for _host in $(echo "$_inv_out" | jq -r ".$_group.hosts.[]"); do
            _needs_create=$(ansible_get_host_var "$_inv_out" "$_host" "create")
            _location=$(ansible_get_host_var "$_inv_out" "$_host" "location")
            if $_needs_create; then
                _host_asterisk=" ${COLOR_WHITE_BOLD}(*)${COLOR_RESET}"
            else
                _host_asterisk="    "
            fi
            echo -e "    $_host$_host_asterisk => ${COLOR_WHITE_BOLD}$_location${COLOR_RESET}"
        done
        
        echo ""
    done

    if [[ $(echo "$_inv_out" | jq -r ".unmanaged") != "null" ]]; then
        # List servers to delete
        echo -e "${COLOR_WHITE_BOLD}Servers to delete${COLOR_RESET}"
        for _host in $(echo "$_inv_out" | jq -r ".unmanaged.hosts.[]"); do
            _ip=$(ansible_get_host_var "$_inv_out" "$_host" "ansible_host")
            echo "  $_host ($_ip)"
        done
    fi
}

# This function displays detailed information about a single node.
# It shows all available information about the specified node.
#
# Arguments:
#   $1 - Inventory output
#   $2 - Node name to show details for
nodes_show_single() {
    local _inv_out="$1"
    local _node_name="$2"
    local _node_group=
    local _found=false
    local _group
    local _host
    local _is_control
    local _is_worker
    local _server_type
    local _image
    local _needs_create
    local _current_ip
    local _upgrade_time
    local _internal_ip

    for _group in $(echo "$_inv_out" | jq -r ". | keys | .[]"); do
        if nodes_should_skip_group "$_group"; then
            continue
        fi

        for _host in $(echo "$_inv_out" | jq -r ".$_group.hosts.[]"); do
            if [[ "$_host" == "$_node_name" ]]; then
                _node_group="$_group"
                _found=true
                break
            fi
        done

        if $_found; then
            break
        fi
    done

    if ! $_found; then
        log_error "Node '$_node_name' not found in inventory"
        exit 1
    fi

    _is_control=$(ansible_get_group_var "$_inv_out" "$_node_group" "is_control")
    _is_worker=$(ansible_get_group_var "$_inv_out" "$_node_group" "is_worker")
    _server_type=$(ansible_get_group_var "$_inv_out" "$_node_group" "type")
    _image=$(ansible_get_group_var "$_inv_out" "$_node_group" "image")
    
    _needs_create=$(ansible_get_host_var "$_inv_out" "$_node_name" "create")
    _current_ip=$(ansible_get_host_var "$_inv_out" "$_node_name" "ansible_host")
    _upgrade_time=$(ansible_get_host_var "$_inv_out" "$_node_name" "upgrade_time")
    _internal_ip=$(ansible_get_host_var "$_inv_out" "$_node_name" "internal_ip")

    echo -e "${COLOR_WHITE_BOLD}$_node_name${COLOR_RESET}"
    echo -e "  Group: ${COLOR_WHITE_BOLD}$_node_group${COLOR_RESET}"
    echo -e "  Is new: ${COLOR_WHITE_BOLD}$(if $_needs_create; then echo "Yes"; else echo "No"; fi)${COLOR_RESET}"
    if ! $_needs_create; then
        echo -e "  Current IP: ${COLOR_WHITE_BOLD}$_current_ip${COLOR_RESET}"
    fi
    echo -e "  Internal IP: ${COLOR_WHITE_BOLD}$_internal_ip${COLOR_RESET}"
    echo -e "  Is Control-Plane: ${COLOR_WHITE_BOLD}$(if $_is_control; then echo "Yes"; else echo "No"; fi)${COLOR_RESET}"
    echo -e "  Is Worker: ${COLOR_WHITE_BOLD}$(if $_is_worker; then echo "Yes"; else echo "No"; fi)${COLOR_RESET}"
    echo -e "  Server-Type: ${COLOR_WHITE_BOLD}$_server_type${COLOR_RESET}"
    echo -e "  OS Image: ${COLOR_WHITE_BOLD}$_image${COLOR_RESET}"
    echo -e "  Time for Reboot: ${COLOR_WHITE_BOLD}$_upgrade_time${COLOR_RESET}"
    echo ""

    # Show cluster volumes if present
    local _volumes_json
    _volumes_json=$(ansible_get_host_var "$_inv_out" "$_node_name" "cluster_volumes")
    if [[ "$_volumes_json" != "null" && -n "$_volumes_json" ]] && echo "$_volumes_json" | jq empty >/dev/null 2>&1; then
        echo -e "  ${COLOR_WHITE_BOLD}Cluster Volumes:${COLOR_RESET}"
        echo "$_volumes_json" | jq -c '.[]' | while read -r _vol; do
            local _name _size _id _needs_create _needs_resize _status
            _name=$(echo "$_vol" | jq -r '.name')
            _size=$(echo "$_vol" | jq -r '.size')
            _id=$(echo "$_vol" | jq -r '.id // "(none)"')
            _needs_create=$(echo "$_vol" | jq -r '.needs_create')
            _needs_resize=$(echo "$_vol" | jq -r '.needs_resize')
            if [[ "$_needs_create" == "true" ]]; then
                _status="to be created"
            elif [[ "$_needs_resize" == "true" ]]; then
                _status="needs resize"
            else
                _status="OK"
            fi
            echo -e "    - Name: ${COLOR_WHITE_BOLD}${_name}${COLOR_RESET}"
            echo -e "      Size: ${COLOR_WHITE_BOLD}${_size}${COLOR_RESET}"
            echo -e "      ID: ${COLOR_WHITE_BOLD}${_id}${COLOR_RESET}"
            echo -e "      Status: ${COLOR_WHITE_BOLD}${_status}${COLOR_RESET}"
        done
        echo ""
    fi
}

register_command "nodes" "List all configured nodes"