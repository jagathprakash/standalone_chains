#!/bin/sh
set -e

dir=$(dirname $0)
source "${dir}"/env.sh

pipelinerun=$(mktemp)
envsubst < "${dir}/pipeline_run.yaml" > "${pipelinerun}"
k_pipeline create --filename "${pipelinerun}"
rm -rf "${pipelinerun}"

# Wait for completion!
tkn pr logs --last -f
