#!/bin/bash

set -e

cd ~/plans/rancher2

start_cloud_cluster() {
  # Provision cluster VM sur cloud
  terraform init
  terraform validate
  terraform plan -out rancher2.plan
  terraform apply -auto-approve rancher2.plan
  terraform show
  # Préparation Rancher2
  inventory-template.sh
  ansible-playbook -v playbook.yml
  ansible-playbook -v playbook-rancher2.yml
}

# https://rancher.com/docs/rancher/v2.x/en/installation/ha/

# Démarrage Kubernetes via RKE
start_k8s_cluster() {
  rancher-cluster-template.sh
  rke up --config ./rancher-cluster.yml
  export KUBECONFIG=$(pwd)/kube_config_rancher-cluster.yml
  kubectl get nodes

  # Installation Helm
  kubectl -n kube-system create serviceaccount tiller
  kubectl create clusterrolebinding tiller \
      --clusterrole=cluster-admin \
      --serviceaccount=kube-system:tiller
  helm init --service-account tiller
  kubectl -n kube-system rollout status deploy/tiller-deploy
  helm version

  # Install cert-manager
  # https://rancher.com/docs/rancher/v2.x/en/installation/ha/helm-rancher/#optional-install-cert-manager
  kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.9/deploy/manifests/00-crds.yaml
  kubectl create namespace cert-manager
  kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
  helm repo add jetstack https://charts.jetstack.io
  helm repo update
  helm install \
      --name cert-manager \
      --namespace cert-manager \
      --version v0.9.1 \
      jetstack/cert-manager
  kubectl -n cert-manager rollout status deploy/cert-manager
  kubectl -n cert-manager rollout status deploy/cert-manager-cainjector
  kubectl -n cert-manager rollout status deploy/cert-manager-webhook
  kubectl get pods --namespace cert-manager

  # Install Rancher
  helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
  helm install rancher-stable/rancher \
    --name rancher \
    --namespace cattle-system \
    --set hostname=$(jq -r '.resources[] | select(.type == "aws_lb") | .instances[].attributes.dns_name' terraform.tfstate)
  kubectl -n cattle-system rollout status deploy/rancher

  # Génération password admin dans rancher_admin_password.txt
  kubectl --kubeconfig $KUBECONFIG -n cattle-system exec $(kubectl --kubeconfig $KUBECONFIG -n cattle-system get pods -l app=rancher | grep '1/1' | head -1 | awk '{ print $1 }') -- reset-password | tail -n 1 > rancher_admin_password.txt
  cat rancher_admin_password.txt

  # Ajout storage-class pour activer l'EBS
  kubectl --kubeconfig $KUBECONFIG apply -f storage_class_aws_gp2_eu-central-1.yml
}

start_cloud_cluster && start_k8s_cluster