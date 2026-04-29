#!/usr/bin/env python3
"""Dynamic Ansible inventory derived from network.yml.

network.yml at the repo root is the single source of truth for all host IPs,
groupings, and group vars. This script reads it and emits Ansible inventory
JSON with no hardcoded values.

Groups produced:
  physical  → one child group per unique `type` value across all nodes
  vms       → one child group per node that defines ansible_group,
              named by ansible_group, with vars from ansible_group_vars

VMs with ansible_managed: false are excluded (e.g. nuc-haos).
"""

import json
import sys
import yaml
from pathlib import Path

NETWORK_FILE = Path(__file__).resolve().parents[2] / "network.yml"


def load_network():
    with open(NETWORK_FILE) as f:
        return yaml.safe_load(f)


def build_inventory(network):
    hostvars = {}
    nodes = network.get("nodes", {})

    # Collect unique physical types for child group list
    physical_types = sorted({attrs.get("type", "other") for attrs in nodes.values()})

    # Collect VM groups from nodes that define ansible_group
    vm_groups = {
        attrs["ansible_group"]: {
            "hosts": [],
            "vars": attrs.get("ansible_group_vars", {}),
        }
        for attrs in nodes.values()
        if "ansible_group" in attrs
    }

    inventory = {
        "_meta": {"hostvars": hostvars},
        "all": {
            "vars": {"ansible_python_interpreter": "/usr/bin/python3"},
            "children": ["physical", "vms"],
        },
        "physical": {"children": physical_types},
        "vms": {"children": list(vm_groups)},
    }

    # Initialise one group per physical type
    for ptype in physical_types:
        inventory[ptype] = {"hosts": []}

    inventory.update(vm_groups)

    for hostname, attrs in nodes.items():
        # Add physical host to its type group
        ptype = attrs.get("type", "other")
        inventory[ptype]["hosts"].append(hostname)

        hvars = {"ansible_host": attrs["ip"]}
        if attrs.get("bridge_port"):
            # Consumed by the network role to configure the Proxmox bridge
            hvars["static_ip"] = f"{attrs['ip']}/24"
        if "ansible_user" in attrs:
            hvars["ansible_user"] = attrs["ansible_user"]
        hostvars[hostname] = hvars

        # Add VMs to their node's ansible_group
        group = attrs.get("ansible_group")
        for vmname, vmattrs in attrs.get("vms", {}).items():
            if not vmattrs.get("ansible_managed", True):
                continue
            if group:
                inventory[group]["hosts"].append(vmname)
                hostvars[vmname] = {"ansible_host": vmattrs["ip"]}

    return inventory


def main():
    network = load_network()
    inventory = build_inventory(network)

    if len(sys.argv) == 3 and sys.argv[1] == "--host":
        print(json.dumps(inventory["_meta"]["hostvars"].get(sys.argv[2], {}), indent=2))
    else:
        print(json.dumps(inventory, indent=2))


if __name__ == "__main__":
    main()
