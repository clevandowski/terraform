#!/usr/bin/env bash

declare -A PRIVATE_INSTANCES
declare -A SUBNETS

set -eo pipefail

export DIRNAME=$(dirname $0)

extract_tfstate_bastion_instance_to_ansible_inventory_hosts() {
  jq '.resources[] | select(.type == "aws_instance")
  | .instances[].attributes
  | select(.tags.Zone == "Public")
  | {
      (.tags.Name): {
        id: .id,
        ansible_host: .public_ip,
      }
    }' terraform.tfstate
}

extract_tfstate_aws_rancher_instances_to_ansible_inventory_hosts() {
  jq '.resources[] | select(.type == "aws_instance")
  | .instances[].attributes
  | select(.tags.Zone == "Private" and .tags.cluster == "rancher2")
  | {
      (.tags.Name): { 
        id: .id,
        ansible_host: .private_ip,
        private_dns: .private_dns,
        private_ip: .private_ip,
        tags: .tags,
      }
    }' terraform.tfstate
}

extract_tfstate_aws_dev_instances_to_ansible_inventory_hosts() {
  jq '.resources[] | select(.type == "aws_instance")
  | .instances[].attributes
  | select(.tags.Zone == "Private" and .tags.cluster == "dev")
  | {
      (.tags.Name): { 
        id: .id,
        ansible_host: .private_ip,
        private_dns: .private_dns,
        private_ip: .private_ip,
        tags: .tags,
      }
    }' terraform.tfstate
}

inject_ansible_inventory_bastion_hosts_json() {
  jq -c '.' \
  | while read line; do
      echo ".all.children.bastion.hosts += $line"
    done
}

inject_ansible_inventory_rancher_hosts_json() {
  # is_first="true"
  jq -c '.' \
  | while read line; do
    # if [ "$is_first" != "false" ]; then
    #   is_first="false"
    #   echo ".all.children.rancher.hosts += $line"
    # else
      echo "| .all.children.rancher.hosts += $line"
      # fi
    done
}

inject_ansible_inventory_dev_hosts_json() {
  # is_first="true"
  jq -c '.' \
  | while read line; do
    # if [ "$is_first" != "false" ]; then
    #   is_first="false"
    #   echo ".all.children.dev.hosts += $line"
    # else
      echo "| .all.children.dev.hosts += $line"
    # fi
    done
}

process_jq_template() {
  # jq "$(extract_tfstate_bastion_instance_to_ansible_inventory_hosts | inject_ansible_inventory_bastion_hosts_json && extract_tfstate_aws_rancher_instances_to_ansible_inventory_hosts | inject_ansible_inventory_rancher_hosts_json)" $DIRNAME/inventory-base.json
  jq "$(extract_tfstate_bastion_instance_to_ansible_inventory_hosts | inject_ansible_inventory_bastion_hosts_json \
    && extract_tfstate_aws_rancher_instances_to_ansible_inventory_hosts | inject_ansible_inventory_rancher_hosts_json \
    && extract_tfstate_aws_dev_instances_to_ansible_inventory_hosts | inject_ansible_inventory_dev_hosts_json)" $DIRNAME/inventory-base.json
}

process_jq_template | json2yaml.sh > inventory.yml