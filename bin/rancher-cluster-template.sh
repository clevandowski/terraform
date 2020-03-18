#!/bin/bash

export DIRNAME=$(dirname $0)

extract_tfstate_id_rsa() {
  ID_RSA_FILE=${TF_RANCHER_ID_RSA_PUB_PATH:-~/.ssh/id_rsa}
  if [ -f terraform.tfvars ]; then
    ID_RSA_FILE=$(grep "rancher_id_rsa_pub_path" terraform.tfvars |  cut -d = -f 2 | tr -d '"' | sed 's/\.[^.]*$//' | tr -d ' ')
  fi

  export ID_RSA_FILE
}

extract_tfstate_aws_controlplane_instances_to_rancher_cluster_nodes() {
  jq '.resources[] | select(.type == "aws_instance" and .instances[].attributes.tags.role_controlplane == "true")
  | .instances[].attributes
  | {
      hostname_override: .tags.Name,
      address: .private_ip,
      user: "ubuntu",
      ssh_key_path: "$ID_RSA_FILE",
      role: [
        "controlplane",
        "etcd",
        "worker"
      ]
    }' terraform.tfstate | envsubst
}

extract_tfstate_aws_worker_instances_to_rancher_cluster_nodes() {
  jq '.resources[] | select(.type == "aws_instance" and .instances[].attributes.tags.role_worker == "true")
  | .instances[].attributes
  | {
      hostname_override: .tags.Name,
      address: .private_ip,
      user: "ubuntu",
      ssh_key_path: "$ID_RSA_FILE",
      role: [
        "worker"
      ],
      taints: [
        {
          key: "node.elasticsearch.io/unschedulable",
          value: "",
          effect: "NoSchedule"
        }
      ],
      labels: {
        elasticsearch: "reserved"
      }
    }' terraform.tfstate
}

format_rancher_cluster_nodes_json() {
  jq -c '.' \
  | while read line; do
    if [ "$is_first" != "false" ]; then
      is_first="false"
      echo ".nodes += [ $line ]"
    else
      echo "| .nodes += [ $line ]"
      fi
    done
}

append_bastion_host() {
  jq '.resources[] | select(.type == "aws_instance")
  | .instances[].attributes
  | select(.tags.Name = "rancher2-nat-instance")
  | select(.public_ip != "")
  | {
      "bastion_host": {
        hostname_override: .tags.Name,
        address: .public_ip,
        user: "ec2-user",
        ssh_key_path: "$ID_RSA_FILE"
      }
    }' terraform.tfstate | envsubst | json2yaml.sh >> rancher-cluster.yml
}


process_jq_template() {
  jq "$((extract_tfstate_aws_controlplane_instances_to_rancher_cluster_nodes && extract_tfstate_aws_worker_instances_to_rancher_cluster_nodes) | format_rancher_cluster_nodes_json)" $DIRNAME/rancher-cluster-base.json
}


extract_tfstate_id_rsa
process_jq_template | envsubst | json2yaml.sh > rancher-cluster.yml
append_bastion_host
