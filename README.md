# Hobby Cluster

A set of tools and scripts for managing a personal Kubernetes cluster on Hetzner Cloud.

## Requirements

- Python 3.8+
- Ansible 2.9+
- Hetzner Cloud account
- Hetzner DNS account
- SSH keys for authentication

## Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/hobby-cluster.git
   cd hobby-cluster
   ```

2. Configure your cluster:
   ```bash
   cp clusters/example.cluster.yml clusters/my-cluster.cluster.yml
   # Edit my-cluster.cluster.yml with your settings
   ```

3. Deploy your cluster:
   ```bash
   ./cluster play -c my-cluster
   ```

## Available Commands

### play
Deploys the cluster. Provisions servers, configures base system and installs Kubernetes.

```bash
# Run the playbook
./cluster play -c my-cluster

# Run in debug mode
./cluster play -c my-cluster -d

# Run in check mode (dry run)
./cluster play -c my-cluster -C
```

Options:
- `-c, --cluster <cluster>`: Cluster configuration to use (**required**)
- `-d, --debug`: Enable debug output (verbose mode)
- `-h, --help`: Show help message
- `    --reinstall`: Reinstalls Python and Ansible dependencies
- `-C, --check`: Run in check mode (dry run)

### volumes
Shows a brief overview of all configured cluster volumes and server they are attached to.

```bash
# Show a summary of all cluster volumes
./cluster volumes -c my-cluster
```

Options:
- `-c, --cluster <cluster>`: Cluster configuration to use (**required**)
- `-d, --debug`: Enable debug output (verbose mode)
- `-h, --help`: Show help message
- `    --reinstall`: Reinstalls Python and Ansible dependencies

### nodes
Lists all configured servers in the cluster or shows details for a specific server.

```bash
# List all nodes
./cluster nodes -c my-cluster

# Show details for a specific node
./cluster nodes -c my-cluster -n node1
```

Options:
- `-c, --cluster <cluster>`: Cluster configuration to use (**required**)
- `-d, --debug`: Enable debug output (verbose mode)
- `-h, --help`: Show help message
- `    --reinstall`: Reinstalls Python and Ansible dependencies
- `-n, --node <node>`: Show details for a specific node

The nodes command displays:
- Node groups and their roles (Control-Plane/Worker)
- Server types and OS images (Single-view)
- Host locations
- Volumes with name, size, ID and status (Single-view)
- New nodes marked with (*)
- Unmanaged servers that will be deleted

### ssh
SSH into a node by name using the cluster inventory.

```bash
# SSH into a node by name (specifying the cluster)
./cluster ssh -c my-cluster <node-name>
```

Options:
- `-c, --cluster <cluster>`: Cluster configuration to use (**required**)
- `-d, --debug`: Enable debug output (verbose mode)
- `-h, --help`: Show help message
- `    --reinstall`: Reinstalls Python and Ansible dependencies

- `<node-name>`: The name of the node to connect to (as shown by `./cluster nodes`)

The ssh command resolves the node's IP address from the inventory and connects as root via SSH. The node must exist in the cluster and have a reachable IP address. The command will use the SSH keys configured in your cluster configuration. If the node does not exist or has no IP, an error will be shown.

### clear
Clears the complete Hetzner project and deletes all ressources

```bash
# Clear cluster
./cluster clear -c my-cluster
```

Options:
- `-c, --cluster <cluster>`: Cluster configuration to use (**required**)
- `-d, --debug`: Enable debug output (verbose mode)
- `-h, --help`: Show help message
- `    --reinstall`: Reinstalls Python and Ansible dependencies

## Configuration

### Vault Password File Handling

By default, all Ansible commands (playbook execution, inventory listing, etc.) use a vault password file to decrypt sensitive variables in your cluster configuration.
Each Ansible command will use the file `clusters/<cluster>.vault.auth` (where `<cluster>` is your cluster name) as vault password file to decrypt the sensitive data.

### Sensitive Data Encryption

To encrypt sensitive data, use the `ansible-vault encrypt_string` command:

```bash
# Encrypt a string
ansible-vault encrypt_string 'your-secret' --name 'hetzner.cloud_token' --vault-password-file 'clusters/my-cluster.vault.auth'

# The output can be directly pasted into the configuration file
```

### Cluster Configuration

Cluster configuration is done through YAML files in the `clusters/` directory. Example:

```yaml
# Node configuration
nodes:
  control_plane:
    num: 3
    type: cx21
    image: debian-12
    is_control: true
    is_worker: false
    locations:
      - nbg1
      - fsn1
      - hel1
    storage: true

  worker:
    num: 3
    type: cx21
    image: debian-12
    is_worker: true

# Cluster volume configuration
volumes:
  - name: storage
    size: 10G

# System update configuration
unattended_upgrades:
  start_time: "02:00"
  end_time: "04:00"

# Network configuration
network:
  # Private network CIDR for internal cluster communication
  private_cidr: 10.0.0.0/24

# Hetzner Cloud configuration
hetzner:
  cloud_token: !vault |
    $ANSIBLE_VAULT;1.1;AES256
    303132333435363738396162636465663031323334353637383961626364656630313233343536373839616263646566
  dns_token: !vault |
    $ANSIBLE_VAULT;1.1;AES256
    303132333435363738396162636465663031323334353637383961626364656630313233343536373839616263646566
  dns_zone: "example.com"

# SSH-keys
ssh_keys:
  my-key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
  other-key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."

# Email configuration
mail:
  admin_mail: admin@example.com
  host: smtp.example.com
  port: 587
  user: example
  domain: example.com
  password: !vault |
    $ANSIBLE_VAULT;1.1;AES256
    303132333435363738396162636465663031323334353637383961626364656630313233343536373839616263646566
```
