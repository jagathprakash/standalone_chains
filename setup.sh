#!/bin/sh
set -e

dir=$(dirname $0)
source "${dir}"/env.sh

# Configure Key Management Service.
# Ensure KMS is available.
gcloud services enable cloudkms.googleapis.com 
echo "Creating a KEYRING ${KEYRING}..."
if gcloud kms keyrings describe "${KEYRING}" --location "us"; then
  echo "KEYRING ${KEYING} found."
else
  gcloud kms keyrings create "${KEYRING}" --location "us"
  echo "KEYRING ${KEYRING} created successfully."
fi

echo "Checking for ${KEY} in ${KEYRING}."
if gcloud kms keys list --keyring=${KEYRING} --location=us | grep $KEY; then
  echo "KEY ${KEY} already exists"
else
  gcloud kms keys create "${KEY}" \
    --keyring "${KEYRING}" \
    --location "us" \
    --purpose "asymmetric-signing" \
    --default-algorithm "rsa-sign-pkcs1-2048-sha256"
  echo "${KEY} created successfully."
fi

# Set up Artifact Registry: create a docker repository and authorize the
# builder to push images to it.
echo "Creating cloud repo ${CLOUD_REPO}"
if gcloud artifacts repositories list | grep "${CLOUD_REPO}"; then
  echo "Repo ${CLOUD_REPO} already exists"
else
  gcloud artifacts repositories create "${CLOUD_REPO}" \
      --repository-format=docker --location="us"
fi

# GCP settings
# Ensure IAM is enabled
echo "Enabling IAM services."
gcloud services enable iam.googleapis.com

# Create a GCloud Service account
echo "Create a Google service account ${GSA_NAME}"
if gcloud iam service-accounts list | grep "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"; then
  echo "GSA ${GSA_NAME} already exists"
else 
  gcloud iam service-accounts create "${GSA_NAME}" \
    --description="Tekton Build-time Service Account" \
    --display-name="Tekton Builder"
  echo "Successfully created a Google service account ${GSA_NAME}"
fi

echo "Provide aritifactregistry.writer access to service account ${GSA_NAME}"
# Provide necessary permissions to the KSA Service account.
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member "serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role "roles/artifactregistry.writer"

echo "Provide cloudkms.cryptoOperator access to service account ${GSA_NAME}"
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member "serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role "roles/cloudkms.cryptoOperator"

echo "Provide cloudkms.viewer access to service account ${GSA_NAME}"
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member "serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role "roles/cloudkms.viewer"

echo "Provide containeranalysis.admin access to service account ${GSA_NAME}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member "serviceAccount:$GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
  --role "roles/containeranalysis.admin"

echo "Adding workloadIndentityUser access to Kubernetes Service Account ${KSA_NAME} for Google Service account ${GSA_NAME}"
gcloud iam service-accounts add-iam-policy-binding $GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com \
  --role "roles/iam.workloadIdentityUser" \
  --member "serviceAccount:$PROJECT_ID.svc.id.goog[$NAMESPACE/$KSA_NAME]"

# Create a cluster for Tekton Pipelines.
if kubectl config get-clusters | grep $CLUSTER_PIPELINE; then
  echo "Cluster ${CLUSTER_PIPELINE} found."
else  
  gcloud container clusters create $CLUSTER_PIPELINE \
    --enable-autoscaling \
    --min-nodes=1 \
    --max-nodes=3 \
    --scopes=cloud-platform \
    --no-issue-client-certificate \
    --project=$PROJECT_ID \
    --region=us-central1 \
    --machine-type=n1-standard-4 \
    --image-type=cos_containerd \
    --num-nodes=1 \
    --cluster-version=latest \
    --workload-pool=$PROJECT_ID.svc.id.goog
fi
# Create a Kubernetes Service account
echo "Create a kubernetes service account ${KSA_NAME} in Pipeline cluster"
if k_pipeline get serviceAccount "${KSA_NAME}"; then
  echo "KSA ${KSA_NAME} already exists"
else 
  k_pipeline create serviceaccount "${KSA_NAME}" --namespace "${NAMESPACE}"
  echo "Successfully created Kubernetes service account ${KSA_NAME} in ${NAMESPACE} in Pipeline cluster."
fi
echo "Adding workloadIndentityUser access to Kubernetes Service Account ${KSA_NAME} for Google Service account ${GSA_NAME}"
gcloud iam service-accounts add-iam-policy-binding $GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com \
  --role "roles/iam.workloadIdentityUser" \
  --member "serviceAccount:$PROJECT_ID.svc.id.goog[$NAMESPACE/$KSA_NAME]"

echo "Annotate the Kubernetes Service Account ${KSA_NAME} to point to the Google Service Account ${GSA_NAME} to use."
k_pipeline annotate serviceaccount $KSA_NAME \
  --overwrite \
  --namespace $NAMESPACE \
  iam.gke.io/gcp-service-account=$GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com

# install pipelines
k_pipeline apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Create a cluster for Tekton Chains.
if kubectl config get-clusters | grep $CLUSTER_CHAINS; then
  echo "Cluster ${CLUSTER_CHAINS} found."
else  
  gcloud container clusters create $CLUSTER_CHAINS \
    --enable-autoscaling \
    --min-nodes=1 \
    --max-nodes=3 \
    --scopes=cloud-platform \
    --no-issue-client-certificate \
    --project=$PROJECT_ID \
    --region=us-central1 \
    --machine-type=n1-standard-4 \
    --image-type=cos_containerd \
    --num-nodes=1 \
    --cluster-version=latest \
    --workload-pool=$PROJECT_ID.svc.id.goog
fi
# Create a Kubernetes Service account in Chains Cluster
echo "Create a kubernetes service account ${KSA_NAME} in Chains Cluster"
if k_chains get serviceAccount "${KSA_NAME}"; then
  echo "KSA ${KSA_NAME} already exists"
else 
  k_chains create serviceaccount "${KSA_NAME}" --namespace "${NAMESPACE}"
  echo "Successfully created Kubernetes service account ${KSA_NAME} in ${NAMESPACE} in Chains Cluster."
fi

k_chains apply -f namespace.yaml
k_chains create configmap kubeconfigmap --from-file=${KUBECONFIG_FILE} -n tekton-chains

k_chains apply -f chains.yaml

gcloud iam service-accounts add-iam-policy-binding $GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com \
  --role "roles/iam.workloadIdentityUser" \
  --member "serviceAccount:$PROJECT_ID.svc.id.goog[tekton-chains/tekton-chains-controller]"

k_chains annotate serviceaccount tekton-chains-controller \
    --overwrite \
    --namespace tekton-chains \
    iam.gke.io/gcp-service-account=$GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com

k_chains patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.pipelinerun.format": "in-toto"}}'
k_chains patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.oci.format": "simplesigning"}}'
k_chains patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.pipelinerun.signer": "kms"}}'
k_chains patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.oci.signer": "kms"}}'
k_chains patch configmap chains-config -n tekton-chains -p="{\"data\":{\"signers.kms.kmsref\": \"${KMS_REF}\"}}"
k_chains patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.pipelinerun.storage": "grafeas"}}'
k_chains patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.oci.storage": "grafeas"}}'
k_chains patch configmap chains-config -n tekton-chains -p='{"data":{"storage.grafeas.projectid": "'"$PROJECT_ID"'"}}'
k_chains patch configmap chains-config -n tekton-chains -p='{"data":{"storage.grafeas.noteid": "tktn_slsa_demo_note"}}'
k_chains patch configmap chains-config -n tekton-chains -p='{"data":{"builder.id": "jagathprakash@google.com"}}'
k_chains patch configmap feature-flags -n tekton-pipelines -p='{"data":{"enable-provenance-in-status": "true"}}'
