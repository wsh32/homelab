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
    tailscale_hosted_domain = network.get('tailscale_hosted_domain', '')

    node_configs = group_config.get('nodes', {})

    hostvars = {}
    groups = {
        'all': {'vars': {
            'ansible_python_interpreter': '/usr/bin/python3',
            'tailscale_hosted_domain': tailscale_hosted_domain,
        }},
        'physical': {'children': []},
        'vms': {'children': []},
        'tailscale_hosted': {'hosts': []},
    }
    physical_type_groups = set()

    # Register VM groups from group_config (location-agnostic)
    for node_name, node_cfg in node_configs.items():
        grp = node_cfg['group']
        if grp not in groups:
            groups['vms']['children'].append(grp)
            groups[grp] = {'hosts': [], 'vars': node_cfg.get('vars', {})}

    for loc_name, loc in network.get('locations', {}).items():
        nodes = loc.get('nodes', {})
        subnet_prefix = loc.get('subnet_prefix', 24)
        tailscale_domain = loc.get('tailscale_domain', '')
        traefik_vm_name = loc.get('traefik_vm', '')
        headscale_vm_name = loc.get('headscale_vm', '')

        # Derive per-location shared values from the node/VM list
        nas_ip = None
        nfs_exports = {}
        traefik_ip = None
        infisical_host = None
        all_location_services = []

        for node_attrs in nodes.values():
            if node_attrs.get('type') == 'nas':
                nas_ip = node_attrs['ip']
                nfs_exports = node_attrs.get('nfs_exports', {})
            for vm_name, vm_attrs in node_attrs.get('vms', {}).items():
                if not vm_attrs.get('ansible_managed', True):
                    continue
                if 'ip' not in vm_attrs:
                    continue
                if vm_name == traefik_vm_name:
                    traefik_ip = vm_attrs['ip']
                vm_ip = vm_attrs['ip']
                for svc in vm_attrs.get('services', []):
                    if svc.get('name') == 'infisical' and not infisical_host:
                        infisical_host = f"http://{vm_ip}:{svc['port']}"
                    all_location_services.append({**svc, 'vm': vm_name, 'vm_ip': vm_ip})

        proxmox_nodes = [{'name': n, 'ip': a['ip']}
                         for n, a in nodes.items() if a.get('type') == 'proxmox' and 'ip' in a]

        # Common extra vars for every host in this location
        loc_vars = {'location': loc_name, 'tailscale_domain': tailscale_domain}
        if nas_ip:
            loc_vars['nas_ip'] = nas_ip
        if traefik_ip:
            loc_vars['traefik_ip'] = traefik_ip
        if infisical_host:
            loc_vars['infisical_host'] = infisical_host
        if loc.get('dns', {}).get('fallback'):
            loc_vars['dns_fallback'] = loc['dns']['fallback']
        if proxmox_nodes:
            loc_vars['proxmox_nodes'] = proxmox_nodes
        if headscale_vm_name:
            loc_vars['headscale_vm'] = headscale_vm_name

        managed_nodes = {h: a for h, a in nodes.items() if a.get('os') != 'truenas'}

        for hostname, attrs in managed_nodes.items():
            connect_via_ts = attrs.get('connect_via_tailscale', False)
            if connect_via_ts:
                fqdn = f"{hostname}.{tailscale_hosted_domain}" if tailscale_hosted_domain else hostname
                ansible_host = fqdn
            else:
                ansible_host = attrs['ip']
            hvars = {'ansible_host': ansible_host, **loc_vars}
            if connect_via_ts:
                hvars['connect_via_tailscale'] = True
                hvars['tailscale_fqdn'] = ansible_host
            if attrs.get('bridge_port') and 'ip' in attrs:
                hvars['static_ip'] = f"{attrs['ip']}/{subnet_prefix}"
            if 'ansible_user' in attrs:
                hvars['ansible_user'] = attrs['ansible_user']
            if attrs.get('vm_bridge_subnet'):
                hvars['ts_bridge_subnet'] = attrs['vm_bridge_subnet']
                hvars['ts_bridge_ip'] = attrs['vm_bridge_ip']
            if attrs.get('tailscale_ssh'):
                hvars['tailscale_ssh'] = True
            hostvars[hostname] = hvars

            if attrs.get('type') == 'proxmox':
                groups['tailscale_hosted']['hosts'].append(hostname)

            # Register physical type group
            ptype = attrs.get('type', 'other')
            if ptype not in physical_type_groups:
                physical_type_groups.add(ptype)
                groups['physical']['children'].append(ptype)
                groups[ptype] = {'hosts': []}
            groups[ptype]['hosts'].append(hostname)

            # {hostname}_all spans the physical host and all its VMs
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

                vm_ansible_host = vmattrs.get('ip') or vmattrs.get('bridge_ip')
                if not vm_ansible_host:
                    continue

                vmhvars = {
                    'ansible_host': vm_ansible_host,
                    **loc_vars,
                    'all_location_services': all_location_services,
                }
                if vmattrs.get('bridge_ip'):
                    vmhvars['bridge_ip'] = vmattrs['bridge_ip']
                if vmattrs.get('tailscale_exit_node'):
                    vmhvars['tailscale_exit_node'] = True
                if 'tailscale_advertise_routes' in vmattrs:
                    vmhvars['tailscale_advertise_routes'] = vmattrs['tailscale_advertise_routes']
                vm_roles = vmattrs.get('vm_roles', [])
                if vm_roles:
                    vmhvars['vm_roles'] = vm_roles
                    for role in vm_roles:
                        if role not in groups:
                            groups[role] = {'hosts': []}
                        groups[role]['hosts'].append(vmname)
                if vmattrs.get('services'):
                    vmhvars['services'] = vmattrs['services']
                if vmattrs.get('nfs_mounts') and nas_ip and nfs_exports:
                    resolved = []
                    for m in vmattrs['nfs_mounts']:
                        export_path = nfs_exports.get(m['export'])
                        if export_path:
                            resolved.append({'source': f"{nas_ip}:{export_path}", 'mount': m['mount']})
                    if resolved:
                        vmhvars['nfs_mounts'] = resolved

                hostvars[vmname] = vmhvars
                if vm_group:
                    groups[vm_group]['hosts'].append(vmname)

    return {**groups, '_meta': {'hostvars': hostvars}}


if __name__ == '__main__':
    if '--host' in sys.argv:
        print(json.dumps({}))
    else:
        print(json.dumps(build_inventory(), indent=2))
