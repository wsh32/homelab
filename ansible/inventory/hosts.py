#!/usr/bin/env python3
"""Dynamic Ansible inventory derived from network.yml.

network.yml at the repo root is the single source of truth for all host IPs
and groupings. This script reads it and emits Ansible inventory JSON,
eliminating the need to keep a separate hosts.yml file in sync.

Groups produced:
  physical        → proxmox, nas, other   (driven by physical[*].type)
  vms             → nuc_vms, anton_vms, services_vms  (driven by vms[*].node)

VMs with ansible_managed: false are excluded (e.g. nuc-haos).
"""

import json
import sys
import yaml
from pathlib import Path

NETWORK_FILE = Path(__file__).resolve().parents[2] / "network.yml"

NODE_TO_GROUP = {
    "nuc": "nuc_vms",
    "anton": "anton_vms",
    "services": "services_vms",
}


def load_network():
    with open(NETWORK_FILE) as f:
        return yaml.safe_load(f)


def build_inventory(network):
    hostvars = {}

    inventory = {
        "_meta": {"hostvars": hostvars},
        "all": {
            "vars": {"ansible_python_interpreter": "/usr/bin/python3"},
            "children": ["physical", "vms"],
        },
        "physical": {"children": ["proxmox", "nas", "other"]},
        "proxmox": {"hosts": []},
        "nas": {"hosts": []},
        "other": {"hosts": []},
        "vms": {"children": list(NODE_TO_GROUP.values())},
        "nuc_vms": {
            "hosts": [],
            "vars": {"proxmox_node": "nuc", "ansible_user": "debian"},
        },
        "anton_vms": {
            "hosts": [],
            "vars": {"proxmox_node": "anton", "ansible_user": "debian"},
        },
        "services_vms": {
            "hosts": [],
            "vars": {"proxmox_node": "services", "ansible_user": "debian"},
        },
    }

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
        group = NODE_TO_GROUP.get(attrs.get("node"))
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
