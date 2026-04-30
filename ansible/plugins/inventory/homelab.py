# GNU General Public License v3.0+

from __future__ import absolute_import, division, print_function
__metaclass__ = type

DOCUMENTATION = r'''
    name: homelab
    plugin_type: inventory
    short_description: Homelab inventory plugin
    description:
        - Reads network.yml and ansible/group_config.yml to build Ansible inventory.
        - Physical nodes are grouped by their C(type) field in network.yml.
        - VMs are grouped according to their parent node's entry in group_config.yml.
    options:
        plugin:
            description: Identifies this file as a source for the homelab plugin.
            required: true
            choices: ['homelab']
'''

import yaml
from pathlib import Path

from ansible.errors import AnsibleParserError
from ansible.plugins.inventory import BaseInventoryPlugin


class InventoryModule(BaseInventoryPlugin):

    NAME = 'homelab'

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(('homelab.yml', 'homelab.yaml'))

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache)
        self._read_config_data(path)

        inv_dir = Path(path).parent    # ansible/inventory/
        ansible_dir = inv_dir.parent   # ansible/
        repo_root = ansible_dir.parent # repo root

        network = self._load_yaml(repo_root / 'network.yml')
        group_config = self._load_yaml(ansible_dir / 'group_config.yml')

        self._populate(network, group_config)

    def _load_yaml(self, path):
        try:
            with open(path) as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            raise AnsibleParserError(f"Required file not found: {path}")
        except yaml.YAMLError as e:
            raise AnsibleParserError(f"YAML error in {path}: {e}")

    def _populate(self, network, group_config):
        nodes = network.get('nodes', {})
        node_configs = group_config.get('nodes', {})
        subnet_prefix = network.get('subnet_prefix', 24)

        self.inventory.set_variable('all', 'ansible_python_interpreter', '/usr/bin/python3')

        # One child group under physical per unique type value
        physical_types = sorted({attrs.get('type', 'other') for attrs in nodes.values()})
        self.inventory.add_group('physical')
        for ptype in physical_types:
            self.inventory.add_group(ptype)
            self.inventory.add_child('physical', ptype)

        # One child group under vms per node entry in group_config
        self.inventory.add_group('vms')
        for node_name, node_cfg in node_configs.items():
            group = node_cfg['group']
            self.inventory.add_group(group)
            self.inventory.add_child('vms', group)
            for var_name, var_val in node_cfg.get('vars', {}).items():
                self.inventory.set_variable(group, var_name, var_val)

        for hostname, attrs in nodes.items():
            self.inventory.add_host(hostname)
            self.inventory.set_variable(hostname, 'ansible_host', attrs['ip'])

            if attrs.get('bridge_port'):
                self.inventory.set_variable(
                    hostname, 'static_ip', f"{attrs['ip']}/{subnet_prefix}"
                )
            if 'ansible_user' in attrs:
                self.inventory.set_variable(hostname, 'ansible_user', attrs['ansible_user'])

            self.inventory.add_child(attrs.get('type', 'other'), hostname)

            node_cfg = node_configs.get(hostname, {})
            vm_group = node_cfg.get('group')

            for vmname, vmattrs in attrs.get('vms', {}).items():
                if not vmattrs.get('ansible_managed', True):
                    continue
                self.inventory.add_host(vmname)
                self.inventory.set_variable(vmname, 'ansible_host', vmattrs['ip'])
                if vm_group:
                    self.inventory.add_child(vm_group, vmname)
