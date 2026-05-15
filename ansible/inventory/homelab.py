#!/usr/bin/env python3
"""Dynamic inventory script for the homelab.

Reads network.yml and ansible/group_config.yml to build Ansible inventory.
Called automatically by Ansible; do not run directly.
"""
import json
import sys
import yaml
from pathlib import Path


def load_yaml(path):
    with open(path) as f:
        return yaml.safe_load(f)


def build_inventory():
    script_dir = Path(__file__).resolve().parent  # ansible/inventory/
    ansible_dir = script_dir.parent               # ansible/
    repo_root = ansible_dir.parent                # repo root

    network = load_yaml(repo_root / 'network.yml')
    group_config = load_yaml(ansible_dir / 'group_config.yml')

    nodes = network.get('nodes', {})
    node_configs = group_config.get('nodes', {})
    subnet_prefix = network.get('subnet_prefix', 24)

    hostvars = {}
    groups = {
        'all': {'vars': {'ansible_python_interpreter': '/usr/bin/python3'}},
    }

    managed_nodes = {h: a for h, a in nodes.items() if a.get('os') != 'truenas'}

    # One child group under physical per unique type value
    physical_types = sorted({attrs.get('type', 'other') for attrs in managed_nodes.values()})
    groups['physical'] = {'children': physical_types}
    for ptype in physical_types:
        groups[ptype] = {'hosts': []}

    # One child group under vms per node entry in group_config
    groups['vms'] = {'children': []}
    for node_name, node_cfg in node_configs.items():
        group = node_cfg['group']
        groups['vms']['children'].append(group)
        groups[group] = {
            'hosts': [],
            'vars': node_cfg.get('vars', {}),
        }

    for hostname, attrs in managed_nodes.items():
        hvars = {'ansible_host': attrs['ip']}
        if attrs.get('bridge_port'):
            hvars['static_ip'] = f"{attrs['ip']}/{subnet_prefix}"
        if 'ansible_user' in attrs:
            hvars['ansible_user'] = attrs['ansible_user']
        hostvars[hostname] = hvars

        # Place in physical type group
        groups[attrs.get('type', 'other')]['hosts'].append(hostname)

        # <hostname>_all spans the physical host and all its VMs
        node_cfg = node_configs.get(hostname, {})
        vm_group = node_cfg.get('group')
        if vm_group:
            groups[f"{hostname}_all"] = {
                'hosts': [hostname],
                'children': [vm_group],
            }

        for vmname, vmattrs in attrs.get('vms', {}).items():
            if not vmattrs.get('ansible_managed', True):
                continue
            hostvars[vmname] = {'ansible_host': vmattrs['ip']}
            if vm_group:
                groups[vm_group]['hosts'].append(vmname)
            vm_roles = vmattrs.get('vm_roles', [])
            if vm_roles:
                hostvars[vmname]['vm_roles'] = vm_roles
                for role in vm_roles:
                    if role not in groups:
                        groups[role] = {'hosts': []}
                    groups[role]['hosts'].append(vmname)

    return {**groups, '_meta': {'hostvars': hostvars}}


if __name__ == '__main__':
    if '--host' in sys.argv:
        print(json.dumps({}))
    else:
        print(json.dumps(build_inventory(), indent=2))
