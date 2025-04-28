#!/usr/bin/env bash
# Ansible helper functions for the cluster management tool
# Version: 1.0.0
#
# Dependencies:
#   - deps.sh (for check_command)
#   - log.sh (for logging functions)
#
# This script provides functions for managing Ansible environment setup.
# It should be sourced by the main script.

# Prevent direct execution of this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Global variables
ANSIBLE_VENV_PATH=".venv"
ANSIBLE_REQUIREMENTS_FILE="requirements.txt"
ANSIBLE_COLLECTIONS_FILE="collections.yml"
ANSIBLE_REQUIREMENTS_HASH_FILE=".venv/.requirements.hash"
ANSIBLE_COLLECTIONS_HASH_FILE=".ansible/.collections.hash"

# This function checks if a file has changed since last run
#
# Arguments:
#   $1 - File to check
#   $2 - Hash file to store/compare against
#
# Returns:
#   0 - File has changed or hash file doesn't exist
#   1 - File hasn't changed
_check_file_changed() {
    local _file="$1"
    local _hash_file="$2"
    local _current_hash
    local _stored_hash

    # Get current file hash
    if ! _current_hash=$(sha256sum "$_file" 2>/dev/null | cut -d' ' -f1); then
        return 0  # File doesn't exist or can't be read, consider it changed
    fi

    # Get stored hash if it exists
    if [[ -f "$_hash_file" ]]; then
        _stored_hash=$(cat "$_hash_file")
    else
        return 0  # No stored hash, consider it changed
    fi

    # Compare hashes
    [[ "$_current_hash" != "$_stored_hash" ]]
}

# This function stores the hash of a file
#
# Arguments:
#   $1 - File to hash
#   $2 - Hash file to store in
#
# Returns:
#   0 - Success
#   1 - Failed to store hash
_store_file_hash() {
    local _file="$1"
    local _hash_file="$2"
    local _hash

    # Get current file hash
    if ! _hash=$(sha256sum "$_file" 2>/dev/null | cut -d' ' -f1); then
        return 1
    fi

    # Store hash
    echo "$_hash" > "$_hash_file"
    return 0
}

# This function sets up a Python virtual environment and installs Ansible and its dependencies.
ansible_prepare() {
    local _python_path
    local _force=$REINSTALL
    local _requirements_changed=false
    local _collections_changed=false

    # Check for Python3 (critical dependency)
    check_command python3

    # Get Python path (we know it exists from the check above)
    _python_path=$(command -v python3)
    log_info "Using Python executable: ${_python_path}"

    # Check for requirements files
    if [[ ! -f "${ANSIBLE_REQUIREMENTS_FILE}" ]]; then
        log_error "Requirements file not found: ${ANSIBLE_REQUIREMENTS_FILE}"
        exit 1
    fi
    if [[ ! -f "${ANSIBLE_COLLECTIONS_FILE}" ]]; then
        log_error "Collections file not found: ${ANSIBLE_COLLECTIONS_FILE}"
        exit 1
    fi

    # Create virtual environment if needed
    if [[ ! -d "${ANSIBLE_VENV_PATH}" ]] || [[ ! -f "${ANSIBLE_VENV_PATH}/bin/activate" ]]; then
        log_info "Installing Python virtual environment"
        if ! "${_python_path}" -m venv "${ANSIBLE_VENV_PATH}"; then
            log_error "Failed to create virtual environment"
            exit 1
        fi
        # Force reinstallation if venv was just created
        _force=true
    fi

    # Activate virtual environment
    # shellcheck disable=SC1091
    if ! source "${ANSIBLE_VENV_PATH}/bin/activate"; then
        log_error "Failed to activate virtual environment"
        exit 1
    fi

    # Set up trap to deactivate virtual environment on exit
    trap 'deactivate' EXIT

    # Check for pip3 in virtual environment
    check_command pip3

    # Upgrade pip
    log_info "Upgrading pip..."
    if ! python3 -m pip install --upgrade pip >/dev/null 2>&1; then
        log_error "Failed to upgrade pip"
        exit 1
    fi

    # Check if requirements have changed
    if _check_file_changed "$ANSIBLE_REQUIREMENTS_FILE" "$ANSIBLE_REQUIREMENTS_HASH_FILE"; then
        _requirements_changed=true
    fi

    # Install requirements with progress indicator if forced, changed, or venv was just created
    if $_force || $_requirements_changed; then
        log_info "Installing Python requirements..."
        local _pip_flags=("--require-virtualenv" "--no-input" "--progress-bar" "on")
        if $_force; then
            _pip_flags+=("--upgrade")
        fi
        if ! pip3 install -r "${ANSIBLE_REQUIREMENTS_FILE}" "${_pip_flags[@]}"; then
            log_error "Failed to install Python requirements"
            exit 1
        fi
        # Store new hash if installation was successful
        _store_file_hash "$ANSIBLE_REQUIREMENTS_FILE" "$ANSIBLE_REQUIREMENTS_HASH_FILE"
    else
        log_info "Skipping Python requirements installation (use --reinstall to force reinstall)"
    fi

    # Check for Ansible commands after requirements are installed
    check_command ansible
    check_command ansible-galaxy

    # Check if collections have changed
    if _check_file_changed "$ANSIBLE_COLLECTIONS_FILE" "$ANSIBLE_COLLECTIONS_HASH_FILE"; then
        _collections_changed=true
    fi

    # Install Ansible collections if forced, changed, or venv was just created
    if $_force || $_collections_changed; then
        log_info "Installing Ansible collections..."
        local _galaxy_flags=""
        if $_force; then
            _galaxy_flags="--force"
        fi
        if ! ansible-galaxy collection install -r "${ANSIBLE_COLLECTIONS_FILE}" $_galaxy_flags; then
            log_error "Failed to install Ansible collections"
            exit 1
        fi
        # Store new hash if installation was successful
        _store_file_hash "$ANSIBLE_COLLECTIONS_FILE" "$ANSIBLE_COLLECTIONS_HASH_FILE"
    else
        log_info "Skipping Ansible collections installation (use --reinstall to force reinstall)"
    fi
}

# This function retrieves a variable value from a group in the inventory.
# It uses jq to extract the variable value from the group's vars section.
# Outputs the variable value to stdout
#
# Arguments:
#   $1 - Inventory JSON (as a string)
#   $2 - Group name
#   $3 - Variable name
ansible_get_group_var() {
    local _inv_json="$1"
    local _group="$2"
    local _var="$3"

    echo "$_inv_json" | jq -r ".$_group.vars.$_var"
}

# This function retrieves a variable value from a host in the inventory.
# It uses jq to extract the variable value from the host's hostvars section.
# Outputs the variable value to stdout
#
# Arguments:
#   $1 - Inventory JSON (as a string)
#   $2 - Host name
#   $3 - Variable name
ansible_get_host_var() {
    local _inv_json="$1"
    local _host="$2"
    local _var="$3"

    echo "$_inv_json" | jq -r "._meta.hostvars.\"$_host\".$_var"
}