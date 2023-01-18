#!/bin/sh
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
export GSA_NAME=jp-gsa
export KSA_NAME=jp-ksa
export CLOUD_REPO=jp-repo
export PROJECT_ID=jagathprakash-test
export KO_DOCKER_REPO='gcr.io/jagathprakash-test'
export CLUSTER_PIPELINE=pipeline 
export CLUSTER_CHAINS=chains
export ZONE=us-central1
export NAMESPACE=default
export KEYRING=pj-keyring
export KEY=pj-key
export KMS_REF=gcpkms://projects/${PROJECT_ID}/locations/us/keyRings/${KEYRING}/cryptoKeys/${KEY}/cryptoKeyVersions/1
export CLUSTER_PIPELINE_FULL_NAME=gke_${PROJECT_ID}_${ZONE}_${CLUSTER_PIPELINE}
export CLUSTER_CHAINS_FULL_NAME=gke_${PROJECT_ID}_${ZONE}_${CLUSTER_CHAINS}
export KUBECONFIG_FILE=/Users/jagathprakash/.kube/config

# ALIASES
alias k_pipeline="kubectl --context=${CLUSTER_PIPELINE_FULL_NAME}"
alias k_chains="kubectl --context=${CLUSTER_CHAINS_FULL_NAME}"