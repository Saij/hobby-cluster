#!/usr/bin/env bash
# Cluster volumes overview command
# Version: 1.0.0
#
# Dependencies:
#   - ansible.sh (for ansible_prepare, ansible_vault_password_option)
#   - log.sh (for logging functions)
#   - catch.sh (for error catching)
#   - array.sh (for array_join)
#
# This script provides a brief overview of all configured cluster volumes.
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# This function handles the volumes command.
# It displays a summary of all cluster volumes and their status per host.
volumes_command() {
    local _inv_out
    local _inv_err
    local -a _args=()

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

    # Aggregate volumes by name using indexed arrays for portability
    local -a VOLUME_ENTRIES=()
    local _entry
    local _processed_hosts="|"

    # Loop over all groups and hosts
    for _group in $(echo "$_inv_out" | jq -r ". | keys | .[]"); do
        if [[ "$_group" == "_meta" || "$_group" == "all" || "$_group" == "unmanaged" ]]; then
            continue
        fi
        
        for _host in $(echo "$_inv_out" | jq -r ".[\"${_group}\"].hosts // [] | .[]"); do
            # Skip if already processed
            if [[ "$_processed_hosts" == *"|$_host|"* ]]; then
                continue
            fi
            _processed_hosts+="$_host|"
            _volumes_json=$(ansible_get_host_var "$_inv_out" "$_host" "cluster_volumes")
            if [[ "$_volumes_json" != "null" && -n "$_volumes_json" ]] && echo "$_volumes_json" | jq empty >/dev/null 2>&1; then
                while read -r _vol; do
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
                    _entry="${_name}|${_size}|${_host}|${_id}|${_status}"
                    VOLUME_ENTRIES+=("$_entry")
                done < <(echo "$_volumes_json" | jq -c '.[]')
            fi
        done
    done

    # Collect unique volume names
    local -a VOLUME_NAMES=()
    local _seen_names="|"
    for _entry in "${VOLUME_ENTRIES[@]}"; do
        _name="$(echo "$_entry" | cut -d'|' -f1)"
        if [[ "$_seen_names" != *"|$_name|"* ]]; then
            VOLUME_NAMES+=("$_name")
            _seen_names+="$_name|"
        fi
    done

    # Print summary grouped by volume name
    for _name in "${VOLUME_NAMES[@]}"; do
        # Find the first entry for this name to get the size
        for _entry in "${VOLUME_ENTRIES[@]}"; do
            if [[ "$_entry" == "${_name}|"* ]]; then
                _size="$(echo "$_entry" | cut -d'|' -f2)"
                break
            fi
        done
        echo -e "${COLOR_WHITE_BOLD}Volume: ${_name} (${_size})${COLOR_RESET}"
        for _entry in "${VOLUME_ENTRIES[@]}"; do
            if [[ "$_entry" == "${_name}|"* ]]; then
                _host="$(echo "$_entry" | cut -d'|' -f3)"
                _id="$(echo "$_entry" | cut -d'|' -f4)"
                _status="$(echo "$_entry" | cut -d'|' -f5)"
                echo -e "  Host: ${COLOR_WHITE_BOLD}${_host}${COLOR_RESET}   ID: ${COLOR_WHITE_BOLD}${_id}${COLOR_RESET}   Status: ${COLOR_WHITE_BOLD}${_status}${COLOR_RESET}"
            fi
        done
        echo ""
    done
}

# Register the command
register_command "volumes" "Show a brief overview of all configured cluster volumes" 