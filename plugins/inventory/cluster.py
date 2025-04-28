from ansible.errors import AnsibleError
from ansible.inventory.manager import InventoryData
from ansible.plugins.inventory import BaseInventoryPlugin
from ansible.utils.display import Display

from ipaddress import IPv6Network, IPv4Network, IPv4Address
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Set
from collections import deque, Counter

from hcloud import Client, APIException
from hcloud.servers.client import BoundServer
from hcloud.volumes.client import BoundVolume

from pprint import pprint
import os

class NetworkManager:
    """
    Manages IPv4 address allocation within a given network.

    This class provides sequential assignment of host IPs and allows reservation
    of specific IPs (e.g., for already existing servers).

    Attributes:
        _network (IPv4Network): The IPv4 network to manage.
        _assigned (set): Set of already assigned/reserved IPv4 addresses.
        _ip_iter (iterator): Iterator over available host IPs.
    """
    def __init__(self, network: str) -> None:
        """
        Initialize the NetworkManager with an IPv4 network.

        Args:
            network: IPv4 network in CIDR notation (e.g., '10.0.0.0/24').

        Raises:
            ValueError: If the network is invalid or not IPv4.
        """
        self._network = IPv4Network(network)
        if self._network.version != 4:
            raise ValueError("Only IPv4 networks are supported.")
        self._assigned = set()
        self._ip_iter = self._host_ip_generator()

    def _host_ip_generator(self):
        """
        Generator for host IPs in the network, skipping reserved/assigned ones.
        """
        for ip in self._network.hosts():
            if ip not in self._assigned:
                yield ip

    def get_next_ip(self) -> str:
        """
        Get the next available host IP in the network.

        Returns:
            The next available IPv4 address as a string.

        Raises:
            RuntimeError: If no available IPs remain.
        """
        while True:
            try:
                ip = next(self._ip_iter)
            except StopIteration:
                raise RuntimeError("No available IPs left in the network.")
            if ip not in self._assigned:
                self._assigned.add(ip)
                return str(ip)

    def reserve_ip(self, ip: str) -> None:
        """
        Reserve a specific IP address (e.g., for an existing server).

        Args:
            ip: The IPv4 address to reserve (as a string).

        Raises:
            ValueError: If the IP is not in the managed network or already reserved.
        """
        ip_addr = IPv4Address(ip)
        if ip_addr not in self._network.hosts():
            raise ValueError(f"IP {ip} is not a valid host address in the network {self._network}")
        if ip_addr in self._assigned:
            raise ValueError(f"IP {ip} is already reserved.")
        self._assigned.add(ip_addr)

class ValueManager:
    """
    Manages a set of values with usage tracking for fair distribution.
    
    This class maintains a set of values and tracks how many times each value has been used.
    It provides methods to get the least used value and to increment the usage count for a specific value.
    This is useful for distributing resources (like server locations) fairly across multiple hosts.
    
    Attributes:
        _values (List[str]): The list of available values to distribute.
        _counts (Counter): A counter tracking how many times each value has been used.
    """
    
    def __init__(self, values: List[str]) -> None:
        """
        Initialize the ValueManager with a list of values.
        
        Args:
            values: A list of string values to be managed and distributed.
            
        Example:
            >>> manager = ValueManager(["fsn1", "nbg1", "hel1"])
            >>> manager._values
            ['fsn1', 'nbg1', 'hel1']
            >>> manager._counts
            Counter({'fsn1': 0, 'nbg1': 0, 'hel1': 0})
        """
        self._values = list(values)
        self._counts = Counter({value: 0 for value in self._values})

    def __repr__(self) -> str:
        """
        Return a string representation of the ValueManager.
        
        Returns:
            A string showing the values and their current usage counts.
            
        Example:
            >>> manager = ValueManager(["fsn1", "nbg1"])
            >>> manager.get_next()  # Uses 'fsn1'
            'fsn1'
            >>> repr(manager)
            "ValueManager(values=['fsn1', 'nbg1'], counts={'fsn1': 1, 'nbg1': 0})"
        """
        return f"ValueManager(values={self._values}, counts={dict(self._counts)})"

    def get_next(self) -> str:
        """
        Get the least used value and increment its usage count.
        
        This method returns the value that has been used the fewest times so far,
        and increments its usage count. This ensures a fair distribution of values
        over time.
        
        Returns:
            The least used value from the available values.
            
        Example:
            >>> manager = ValueManager(["fsn1", "nbg1", "hel1"])
            >>> manager.get_next()
            'fsn1'
            >>> manager.get_next()
            'nbg1'
            >>> manager.get_next()
            'hel1'
            >>> manager.get_next()  # Back to the least used
            'fsn1'
        """
        min_value = min(self._counts.items(), key=lambda x: x[1])[0]
        self._counts[min_value] += 1
        return min_value

    def increment(self, item: str) -> None:
        """
        Increment the usage count for a specific value.
        
        This method is used when a value has been used externally and needs
        to be tracked in the usage counts.
        
        Args:
            item: The value whose usage count should be incremented.
            
        Raises:
            ValueError: If the item is not in the list of managed values.
            
        Example:
            >>> manager = ValueManager(["fsn1", "nbg1"])
            >>> manager.increment("fsn1")
            >>> manager._counts["fsn1"]
            1
            >>> manager.increment("unknown")  # Raises ValueError
            ValueError: Item 'unknown' not found!
        """
        if item not in self._values:
            raise ValueError(f"Item '{item}' not found!")
        
        self._counts[item] += 1

class HostTimeAssigner:
    """
    Assigns time slots to host groups for fair distribution of maintenance windows.
    
    This class distributes time slots across a specified time window to different host groups,
    ensuring a fair distribution that minimizes the impact of maintenance operations.
    It uses a round-robin approach to assign slots to groups based on their size.
    
    Attributes:
        _start_time (datetime): The start time of the maintenance window.
        _end_time (datetime): The end time of the maintenance window.
        _groups (Dict[str, int]): Dictionary mapping group names to their host counts.
        _total_hosts (int): Total number of hosts across all groups.
        _group_slots (Dict[str, List[datetime]]): Time slots assigned to each group.
        _group_slot_index (Dict[str, int]): Current index for each group's slot list.
        
    Example:
        >>> assigner = HostTimeAssigner({
        ...     "control": 3,
        ...     "worker_small": 2,
        ...     "worker_big": 1
        ... }, "02:00", "03:00")
        >>> assigner.get_all_slots("control")
        ['02:00', '02:36', '03:00']
        >>> assigner.get_all_slots("worker_small")
        ['02:12', '02:48']
        >>> assigner.get_all_slots("worker_big")
        ['02:24']
    """
    
    def __init__(self, groups: Dict[str, int], start_time_str: str, end_time_str: str) -> None:
        """
        Initialize the time assigner with group counts and time window.
        
        Args:
            groups: Dictionary mapping group names to their counts.
            start_time_str: Start time in HH:MM format.
            end_time_str: End time in HH:MM format.
            
        Raises:
            ValueError: If the time window is invalid or not enough minutes for all hosts.
            
        Example:
            >>> assigner = HostTimeAssigner({
            ...     "control": 3,
            ...     "worker_small": 2,
            ...     "worker_big": 1
            ... }, "02:00", "03:00")
            >>> assigner.get_next_slot("control")
            '02:00'
        """
        try:
            self._start_time = datetime.strptime(start_time_str, "%H:%M")
            self._end_time = datetime.strptime(end_time_str, "%H:%M")
        except ValueError as e:
            raise ValueError(f"Invalid time format. Expected HH:MM, got '{start_time_str}' or '{end_time_str}'") from e
            
        if self._end_time <= self._start_time:
            raise ValueError(f"End time '{end_time_str}' must be after start time '{start_time_str}'")
            
        self._groups = groups
        self._total_hosts = sum(groups.values())
        
        if self._total_hosts == 0:
            raise ValueError("No hosts defined in any group")
            
        self._group_slots: Dict[str, List[datetime]] = {}
        self._group_slot_index: Dict[str, int] = {}

        total_minutes = int((self._end_time - self._start_time).total_seconds() // 60)
        if self._total_hosts > total_minutes:
            raise ValueError(f"Not enough minutes in time window for all hosts. Need {self._total_hosts}, have {total_minutes}.")

        # Generate time slots
        if self._total_hosts <= 1:
            all_slots = [self._start_time]
        else:
            step = total_minutes // (self._total_hosts - 1)
            all_slots = [
                self._start_time + timedelta(minutes=i * step)
                for i in range(self._total_hosts)
            ]

        # Create fair distribution of groups
        round_robin = self._interleave_groups(groups.copy())

        # Assign slots to groups
        for group in groups:
            self._group_slots[group] = []
            self._group_slot_index[group] = 0

        for slot, group in zip(all_slots, round_robin):
            self._group_slots[group].append(slot)

    def _interleave_groups(self, group_counts: Dict[str, int]) -> List[str]:
        """
        Creates a fair round-robin distribution of group names.
        
        This method takes a dictionary of group counts and returns a list where
        each group appears the specified number of times, distributed as evenly
        as possible.
        
        Args:
            group_counts: Dictionary mapping group names to their counts.
            
        Returns:
            List of group names in fair distribution order.
            
        Example:
            >>> assigner = HostTimeAssigner({
            ...     "control": 3,
            ...     "worker_small": 2,
            ...     "worker_big": 1
            ... }, "02:00", "03:00")
            >>> assigner._interleave_groups({"control": 3, "worker_small": 2, "worker_big": 1})
            ['control', 'worker_small', 'worker_big', 'control', 'worker_small', 'control']
        """
        result = []
        while group_counts:
            for group in list(group_counts.keys()):
                result.append(group)
                group_counts[group] -= 1
                if group_counts[group] == 0:
                    del group_counts[group]
        return result

    def get_next_slot(self, group_name: str) -> str:
        """
        Get the next available time slot for a group.
        
        Args:
            group_name: Name of the group.
            
        Returns:
            Time slot as string in HH:MM format.
            
        Raises:
            ValueError: If group is unknown or no slots are available.
            
        Example:
            >>> assigner = HostTimeAssigner({
            ...     "control": 3,
            ...     "worker_small": 2,
            ...     "worker_big": 1
            ... }, "02:00", "03:00")
            >>> assigner.get_next_slot("control")
            '02:00'
            >>> assigner.get_next_slot("worker_small")
            '02:12'
            >>> assigner.get_next_slot("worker_big")
            '02:24'
            >>> assigner.get_next_slot("control")
            '02:36'
            >>> assigner.get_next_slot("worker_small")
            '02:48'
            >>> assigner.get_next_slot("control")
            '03:00'
        """
        if group_name not in self._group_slots:
            raise ValueError(f"Unknown group: {group_name}")

        idx = self._group_slot_index[group_name]
        if idx >= len(self._group_slots[group_name]):
            raise ValueError(f"All slots for group '{group_name}' have been assigned.")

        slot = self._group_slots[group_name][idx]
        self._group_slot_index[group_name] += 1
        return slot.strftime("%H:%M")
    
    def get_all_slots(self, group_name: str) -> List[str]:
        """
        Get all time slots assigned to a group.
        
        Args:
            group_name: Name of the group.
            
        Returns:
            List of time slots as strings in HH:MM format.
            
        Raises:
            ValueError: If group is unknown.
            
        Example:
            >>> assigner = HostTimeAssigner({
            ...     "control": 3,
            ...     "worker_small": 2,
            ...     "worker_big": 1
            ... }, "02:00", "03:00")
            >>> assigner.get_all_slots("control")
            ['02:00', '02:36', '03:00']
            >>> assigner.get_all_slots("worker_small")
            ['02:12', '02:48']
            >>> assigner.get_all_slots("worker_big")
            ['02:24']
        """
        if group_name not in self._group_slots:
            raise ValueError(f"Unknown group: {group_name}")
            
        return [slot.strftime("%H:%M") for slot in self._group_slots[group_name]]

class InventoryModule(BaseInventoryPlugin):
    """
    Ansible inventory plugin for managing Hetzner Cloud servers in a cluster configuration.
    
    This plugin dynamically generates an Ansible inventory based on a configuration file
    and the current state of servers in Hetzner Cloud. It supports:
    
    - Multiple node groups (control plane, workers, etc.)
    - Automatic server discovery and matching
    - Fair distribution of server locations
    - Scheduled maintenance windows
    - Automatic IP address assignment
    
    The plugin reads a YAML configuration file that defines the cluster structure,
    including node groups, server types, images, and maintenance windows.
    
    Attributes:
        NAME (str): The name of the inventory plugin.
        _hetzner_servers_configured (List[int]): List of Hetzner server IDs that are still
            managed by this script and should not be deleted during cleanup operations.
        _hetzner_volumes_configured (List[str]): Track managed volume names
        _hcloud_servers (List[BoundServer]): List of Hetzner Cloud server objects.
        _hcloud_volumes (List[BoundVolume]): List of Hetzner Cloud volume objects.
        _inventory (InventoryData): Ansible inventory object.
        _config (Dict[str, Any]): Configuration data from the inventory file.
        _host_time_assigner (HostTimeAssigner): Assigner for maintenance windows.
        _network_manager (NetworkManager): Manager for private network.
    """
    
    NAME = "cluster"

    ####################
    # Class Management #
    ####################

    def __init__(self) -> None:
        """Initialize the inventory plugin."""
        super(InventoryModule, self).__init__()
        self._hetzner_servers_configured: List[int] = []
        self._hetzner_volumes_configured: List[str] = []
        self._hcloud_servers: List[BoundServer] = []
        self._hcloud_volumes: List[BoundVolume] = []
        self._inventory: InventoryData
        self._config: Dict[str, Any]
        self._host_time_assigner: HostTimeAssigner
        self._network_manager: NetworkManager

    ############################
    # Configuration Management #
    ############################

    def _get_config(self, key: str, default: Any = None, config: Optional[Dict[str, Any]] = None, initial_key: Optional[str] = None) -> Any:
        """
        Get configuration value using dot notation for nested keys.
        
        This method allows accessing nested configuration values using dot notation.
        For example, "nodes.control.type" will return the server type for the control group.
        
        Args:
            key: Configuration key, can use dot notation for nested keys.
            default: Default value if key not found.
            config: Optional config dict to search in (defaults to self._config).
            initial_key: For internal recursion.
            
        Returns:
            Configuration value or default.
            
        Example:
            >>> self._config = {"nodes": {"control": {"type": "cx21"}}}
            >>> self._get_config("nodes.control.type")
            'cx21'
            >>> self._get_config("nodes.worker.type", "cx11")
            'cx11'
        """
        config = self._config if config is None else config
        initial_key = key if initial_key is None else initial_key
        
        keys = []
        if "." in key:
            keys = key.split(".")
            key = keys.pop(0)
            
        if key not in config:
            return default
        
        if keys:
            return self._get_config(key=".".join(keys), default=default, config=config[key], initial_key=initial_key)
        else:
            return default if config[key] is None else config[key]

    def _get_group_config(self, group: str, key: str, default: Any = None) -> Any:
        """
        Get configuration for a specific group.
        
        This is a convenience method for accessing group-specific configuration.
        
        Args:
            group: Group name.
            key: Configuration key.
            default: Default value if not found.
            
        Returns:
            Group configuration value.
            
        Example:
            >>> self._config = {"nodes": {"control": {"type": "cx21"}}}
            >>> self.get_group_config("control", "type")
            'cx21'
            >>> self.get_group_config("worker", "type", "cx11")
            'cx11'
        """
        return self._get_config(key=f"nodes.{group}.{key}", default=default)

    ############################
    # Hetzner Cloud Management #
    ############################

    def _load_hcloud_data(self) -> None:
        """
        Load server data from Hetzner Cloud API.
        
        This method authenticates with the Hetzner Cloud API and retrieves
        all servers associated with the account.
        
        Raises:
            AnsibleError: If API token is missing or API request fails.
        """
        api_token = self._get_config(key="hetzner.token.cloud")
        if not api_token:
            raise AnsibleError("No Hetzner Cloud API token specified!")
        
        client = Client(
            token=api_token,
            application_name="hobby-cluster"
        )

        try:
            self._hcloud_servers = client.servers.get_all()
            self._hcloud_volumes = client.volumes.get_all()
        except APIException as exception:
            raise AnsibleError(f"[hcloud] Error requesting Hetzner Cloud API: {exception}") from exception

    def _get_current_ip(self, server: BoundServer) -> str:
        """
        Get the current IP address for a server.
        
        This method returns the primary IPv4 address if available,
        otherwise it returns the first IPv6 address from the network.
        
        Args:
            server: Hetzner server object.
            
        Returns:
            IP address as string.
            
        Raises:
            AnsibleError: If server has no primary network configured.
        """
        if server.public_net.primary_ipv4 is not None:
            return server.public_net.primary_ipv4.ip
        elif server.public_net.primary_ipv6 is not None:
            network = IPv6Network(server.public_net.primary_ipv6.ip)
            return network[1].compressed
        else:
            raise AnsibleError(f"Server {server.name} has no primary network configured!")

    #######################
    # Ansible Integration #
    #######################
        
    def verify_file(self, path: str) -> bool:
        """
        Check if the file is valid for this plugin.
        Ensures the file is directly in the clusters/ directory and matches the *.cluster.yml pattern.
        
        Args:
            path: Path to the inventory file.
            
        Returns:
            True if file is valid.
        """
        filename = os.path.basename(path)
        if os.path.basename(os.path.dirname(path)) != "clusters":
            return False
        if not filename.endswith(".cluster.yml"):
            return False
        return super(InventoryModule, self).verify_file(path)

    def parse(self, inventory: InventoryData, loader: Any, path: str, cache: bool = True) -> None:
        """
        Parse the inventory file and populate the inventory.
        
        This is the main entry point for the inventory plugin. It reads the
        configuration file, loads server data from Hetzner Cloud, and populates
        the Ansible inventory with hosts and groups.
        
        Args:
            inventory: Ansible inventory object.
            loader: Ansible loader.
            path: Path to inventory file.
            cache: Whether to use cached results.
            
        Raises:
            AnsibleError: If required groups are missing or configuration is invalid.
        """
        # Call base method to ensure properties are available
        super(InventoryModule, self).parse(inventory, loader, path, cache)

        # Prepare necessary data
        self._config = self._read_config_data(path)
        self._validate_config_structure(self._config)

        # Now load Hetzner data for logic validation
        self._load_hcloud_data()
        self._validate_config_logic(self._config)
        
        self._inventory = inventory

        # Initialize inventory
        self._initialize_inventory()

    ###########################
    # Inventory Management    #
    ###########################

    def _search_fitting_server(self, name: str, server_type: str, image: str, is_control: bool, is_worker: bool) -> Optional[BoundServer]:
        """
        Search for a server that matches the given criteria.
        
        This method searches for a server in Hetzner Cloud that matches
        the given name, server type, image, and role (control/worker), and has an internal_ip label.
        
        Args:
            name: Server name.
            server_type: Server type.
            image: Server image.
            is_control: Whether server should be part of control plane.
            is_worker: Whether server should be part of worker nodes.
            
        Returns:
            Matching server or None if not found.
        """
        for server in self._hcloud_servers:
            if server.name == name:
                current_image = server.labels.get("image")
                current_type = server.labels.get("server_type")
                current_is_control = server.labels.get("is_control")
                current_is_worker = server.labels.get("is_worker")
                internal_ip = server.labels.get("internal_ip")

                is_delete_control = current_is_control == "true" and not is_control
                is_delete_worker = current_is_worker == "true" and not is_worker

                if (current_image == image and 
                    current_type == server_type and 
                    not is_delete_control and 
                    not is_delete_worker and
                    internal_ip):
                    return server
        return None

    def _validate_config_structure(self, config: dict) -> None:
        """
        Validate the structure and required keys of the cluster configuration file.
        Raises AnsibleError if any required key or structure is missing.
        """
        if not self._get_config("nodes"):
            raise AnsibleError("'nodes' must be a non-empty dictionary in cluster config.")
        if not self._get_config("hetzner.token.cloud"):
            raise AnsibleError("Missing 'hetzner.token.cloud' in cluster config.")
        if not self._get_config("unattended_upgrades.start_time") or not self._get_config("unattended_upgrades.end_time"):
            raise AnsibleError("Missing 'unattended_upgrades.start_time' or 'end_time' in cluster config.")

        has_control = has_worker = False
        control_count = 0
        for group in self._get_config("nodes"):
            is_control = self._get_group_config(group, "is_control")
            is_worker = self._get_group_config(group, "is_worker")
            if not (is_control or is_worker):
                raise AnsibleError(f"Node group '{group}' must have at least one of 'is_control' or 'is_worker' set to true.")
            if is_control:
                has_control = True
                num = self._get_group_config(group, "num")
                if num is not None:
                    control_count += int(num)
            if is_worker:
                has_worker = True
            if not self._get_group_config(group, "type"):
                raise AnsibleError(f"Node group '{group}' missing required key: 'type'.")
            if self._get_group_config(group, "num") is None:
                raise AnsibleError(f"Node group '{group}' missing required key: 'num'.")
        if not has_control:
            raise AnsibleError("At least one node group must have 'is_control: true'.")
        if not has_worker:
            raise AnsibleError("At least one node group must have 'is_worker: true'.")

        # etcd best practices: allow 1, 3, 5, ... control plane nodes, but never 2
        if control_count == 2:
            raise AnsibleError("Invalid control plane configuration: etcd does not support 2 control plane nodes. Use 1 or an odd number >= 3.")

        # Validate volumes section
        volumes = self._get_config("volumes", [])
        for v in volumes:
            if not isinstance(v, dict):
                raise AnsibleError("Each volume entry must be a dictionary.")
            if "name" not in v or not v["name"]:
                raise AnsibleError("Each volume must have a 'name' field.")
            if "size" not in v or not v["size"]:
                raise AnsibleError("Each volume must have a 'size' field.")

    def _validate_config_logic(self, config: dict) -> None:
        """
        Validate logical constraints in the configuration that require external data (e.g., Hetzner state).
        Raises AnsibleError if any logical error is found.
        """
        volumes = self._get_config("volumes", [])
        for group in self._get_config("nodes"):
            if self._get_group_config(group, "storage", False):
                num_hosts = self._get_group_config(group, "num", 0)
                for host in range(1, num_hosts + 1):
                    hostname = f"{group.replace('_', '-')}-{host}"
                    for v in volumes:
                        vol_name = v["name"]
                        vol_size = v["size"]
                        expected_name = f"{hostname}_{vol_name}"
                        matched = None
                        for hv in getattr(self, '_hcloud_volumes', []):
                            if hv.name == expected_name:
                                matched = hv
                                break
                        if matched:
                            config_gb = int(str(vol_size).rstrip("Gg"))
                            if config_gb < matched.size:
                                raise AnsibleError(f"Volume shrinking is not supported: {expected_name} (configured: {config_gb}G, current: {matched.size}G)")
            
    def _initialize_inventory(self) -> None:
        """
        Initialize the inventory with groups and hosts.
        
        This method sets up the inventory structure, including:
        - Adding base groups (controlplane, worker, managed, unmanaged)
        - Initializing the time assigner
        - Processing each group from the configuration
        - Handling unmanaged servers
        - Setting default user
        - Initializing private network manager and reserving existing internal IPs
        
        Raises:
            AnsibleError: If group configuration is invalid or required groups are missing.
        """
        # Add base groups
        self._inventory.add_group("controlplane")
        self._inventory.add_group("worker")
        self._inventory.add_group("managed")
        self._inventory.add_group("unmanaged")

        # Initialize time assigner
        self._init_host_time_assigner()

        # Initialize private network manager
        self._network_manager = NetworkManager(self._get_config("network.private_cidr", "10.0.0.0/24"))

        # Reserve all internal_ip labels from existing servers
        for server in self._hcloud_servers:
            internal_ip = server.labels.get("internal_ip")
            if internal_ip:
                try:
                    self._network_manager.reserve_ip(internal_ip)
                except ValueError as e:
                    # Log or raise as appropriate; here we raise for safety
                    raise AnsibleError(f"Failed to reserve internal_ip {internal_ip} for server {server.name}: {e}")

        # Process each group
        for group in self._config["nodes"]:
            self._prepare_group(group)

        # After all hosts/volumes are processed, find orphaned volumes
        self._set_orphan_volumes_for_cleanup()
        
        # Handle unmanaged servers
        self._clean_hetzner_server()
        
        # Set default user
        self._inventory.set_variable("all", "ansible_user", "root")

    def _init_host_time_assigner(self) -> None:
        """
        Initialize the host time assigner with group configurations.
        
        This method creates a HostTimeAssigner instance to distribute
        maintenance windows across the cluster nodes.
        
        Raises:
            AnsibleError: If start or end time is not specified.
        """
        groups = {
            group: self._get_group_config(group, "num", 0) for group in self._get_config("nodes")
        }

        start_time = self._get_config("unattended_upgrades.start_time")
        end_time = self._get_config("unattended_upgrades.end_time")
        if start_time is None or end_time is None:
            raise AnsibleError("You must specify a start and end time for unattended upgrades")

        self._host_time_assigner = HostTimeAssigner(groups, start_time, end_time)

    def _clean_hetzner_server(self) -> None:
        """
        Identify and mark unmanaged Hetzner servers.
        
        This method identifies servers in Hetzner Cloud that are not
        managed by this inventory plugin and adds them to the "unmanaged"
        group with a "remove-" prefix to their name.
        """
        for server in self._hcloud_servers:
            if server.id not in self._hetzner_servers_configured:
                # Server is not managed by us (anymore?)
                new_name = f"remove-{server.name}" if not server.name.startswith("remove-") else server.name

                self._inventory.add_host(new_name, "unmanaged")
                self._inventory.set_variable(new_name, "old_name", server.name)
                self._inventory.set_variable(new_name, "ansible_host", self._get_current_ip(server))

    def _prepare_group(self, group: str) -> None:
        """
        Prepare a server group with its configuration.
        
        This method sets up a group in the inventory with its configuration,
        including server type, image, and number of hosts. It also creates
        a ValueManager for distributing server locations.
        
        Args:
            group: Group name.
            
        Raises:
            AnsibleError: If group configuration is invalid.
        """
        self._inventory.add_group(group)

        is_control = self._get_group_config(group, "is_control", False)
        is_worker = self._get_group_config(group, "is_worker", False)
        self._inventory.set_variable(group, "is_control", is_control)
        self._inventory.set_variable(group, "is_worker", is_worker)
        
        server_type = self._get_group_config(group, "type")
        if not server_type:
            raise AnsibleError(f"Group {group} has no server type specified!")
        self._inventory.set_variable(group, "type", server_type)

        image = self._get_group_config(group, "image", "debian-12")
        if not image:
            raise AnsibleError(f"Group {group} has no image specified!")
        self._inventory.set_variable(group, "image", image)

        num_hosts = self._get_group_config(group, "num")
        if num_hosts is None:
            raise AnsibleError(f"No hosts for group {group} defined!")

        locations = self._get_group_config(group, "locations", ["fsn1", "nbg1", "hel1"])
        location_manager = ValueManager(locations)

        for host in range(1, num_hosts + 1):
            self._add_host(group, host, location_manager, server_type, image, is_control, is_worker)

    def _add_host(self, group: str, host: int, location_manager: ValueManager, server_type: str, image: str, is_control: bool, is_worker: bool) -> None:
        """
        Add a host to the inventory with its configuration.
        
        This method adds a host to the inventory with its configuration,
        including server type, image, location, maintenance window, and internal IP.
        It also adds the host to the appropriate groups (controlplane, worker, managed).
        
        Args:
            group: Group name.
            host: Host number.
            location_manager: Manager for location distribution.
            server_type: Server type.
            image: Server image.
            is_control: Whether host is part of control plane.
            is_worker: Whether host is part of worker nodes.
        """
        hostname = f"{group.replace('_', '-')}-{host}"
        found_server = self._search_fitting_server(hostname, server_type, image, is_control, is_worker)

        # Assign location
        if found_server is not None:
            self._hetzner_servers_configured.append(found_server.id)
            location = found_server.labels.get("location")
            location_manager.increment(location)
        else:
            location = location_manager.get_next()

        # Assign internal_ip
        if found_server is not None:
            internal_ip = found_server.labels["internal_ip"]
            # Already reserved in _initialize_inventory, but double-check
            try:
                self._network_manager.reserve_ip(internal_ip)
            except ValueError:
                pass  # Already reserved, ignore
        else:
            internal_ip = self._network_manager.get_next_ip()

        self._inventory.add_host(hostname, group)
        self._inventory.set_variable(hostname, "create", found_server is None)
        self._inventory.set_variable(hostname, "location", location)
        self._inventory.set_variable(hostname, "internal_ip", internal_ip)
        self._inventory.set_variable(
            hostname, 
            "upgrade_time", 
            self._host_time_assigner.get_next_slot(group)
        )

        if found_server is not None:
            self._inventory.set_variable(hostname, "ansible_host", self._get_current_ip(found_server))

        if is_control:
            self._inventory.add_child("controlplane", hostname)
        if is_worker:
            self._inventory.add_child("worker", hostname)

        self._inventory.add_child("managed", hostname)

        # Set cluster_volumes if this group is responsible for storage
        if self._get_group_config(group, "storage", False):
            config_volumes = self._get_config("volumes", [])
            host_volumes = []
            for v in config_volumes:
                vol_name = v["name"]
                vol_size = v["size"]
                expected_name = f"{hostname}_{vol_name}"
                matched = None
                for hv in self._hcloud_volumes:
                    if hv.name == expected_name:
                        matched = hv
                        break
                # Track managed volume names
                self._hetzner_volumes_configured.append(expected_name)
                entry = {
                    "name": vol_name,
                    "size": vol_size,
                    "id": matched.id if matched else None,
                    "needs_create": matched is None,
                    "needs_resize": False
                }
                if matched:
                    # Compare size (Hetzner size is in GB as int)
                    # Config size may be '10G', '20G', etc.
                    config_gb = int(str(vol_size).rstrip("Gg"))
                    if matched.size != config_gb:
                        entry["needs_resize"] = True
                host_volumes.append(entry)
            self._inventory.set_variable(hostname, "cluster_volumes", host_volumes)

    def _set_orphan_volumes_for_cleanup(self) -> None:
        """
        Identify orphaned (unmanaged) volumes and set them as a variable for all hosts.
        This allows cleanup roles to access and remove volumes not managed by the current config.
        """
        managed_set = set(self._hetzner_volumes_configured)
        orphan_vols = []
        for hv in self._hcloud_volumes:
            if hv.name not in managed_set:
                orphan_vols.append({
                    "id": hv.id,
                    "name": hv.name,
                    "size": hv.size
                })
        if orphan_vols:
            self._inventory.set_variable("all", "orphan_volumes", orphan_vols)