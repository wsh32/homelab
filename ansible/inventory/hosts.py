#!/usr/bin/env python3
"""Dynamic Ansible inventory derived from network.yml.

network.yml at the repo root is the single source of truth for all host IPs,
groupings, and group vars. This script reads it and emits Ansible inventory
JSON with no hardcoded values.

Groups produced:
  physical  → one child group per unique `type` value in physical[*].type
  vms       → one child group per entry in nodes[*], named nodes[*].group,
              with vars from nodes[*].vars

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

    # Collect unique physical types to create child groups dynamically
    physical_types = sorted({
        attrs.get("type", "other")
        for attrs in network.get("physical", {}).values()
    })

    # Build node → group mapping and VM groups from nodes section
    nodes = network.get("nodes", {})
    node_to_group = {name: cfg["group"] for name, cfg in nodes.items()}
    vm_groups = {
        cfg["group"]: {"hosts": [], "vars": cfg.get("vars", {})}
        for cfg in nodes.values()
    }

    inventory = {
        "_meta": {"hostvars": hostvars},
        "all": {
            "vars": {"ansible_python_interpreter": "/usr/bin/python3"},
            "children": ["physical", "vms"],
        },
        "physical": {"children": physical_types},
        "vms": {"children": list(node_to_group.values())},
    }

    # Initialise one group per physical type
    for ptype in physical_types:
        inventory[ptype] = {"hosts": []}

    # Merge VM groups into inventory
    inventory.update(vm_groups)

    # Physical nodes — grouped by type field
    for hostname, attrs in network.get("physical", {}).items():
        group = attrs.get("type", "other")
        inventory[group]["hosts"].append(hostname)

        hvars = {"ansible_host": attrs["ip"]}
        if attrs.get("bridge_port"):
            # Consumed by the network role to configure the Proxmox bridge
            hvars["static_ip"] = f"{attrs['ip']}/24"
        if "ansible_user" in attrs:
            hvars["ansible_user"] = attrs["ansible_user"]
        hostvars[hostname] = hvars

    # VMs — grouped by node field; excluded if ansible_managed: false
    for vmname, attrs in network.get("vms", {}).items():
        if not attrs.get("ansible_managed", True):
            continue
        group = node_to_group.get(attrs.get("node"))
        if group:
            inventory[group]["hosts"].append(vmname)
            hostvars[vmname] = {"ansible_host": attrs["ip"]}

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
