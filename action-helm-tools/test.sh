#!/bin/bash -l
set -eo pipefail

source $SCRIPT_DIR/common.sh

install_kubectl
install_helm
install_yq
get_component_properties
setup_kind
add_helm_repos

echo "==> Deploy chart $CHART_NAME"
kubectl create namespace $CHART_NAME

if [[ -n "$K8S_DOCKER_REGISTRY_SECRET" ]]; then
    if [[ -n "$GITHUB_USER" ]] && [[ -n "$GITHUB_TOKEN" ]] && [[ "$K8S_DOCKER_REGISTRY" == "$DOCKER_DEV_REGISTRY" ]]; then
        echo "====> Create secret for docker registry (registry is $DOCKER_DEV_REGISTRY)"
        kubectl create secret docker-registry --namespace $CHART_NAME $K8S_DOCKER_REGISTRY_SECRET \
            --docker-server=$K8S_DOCKER_REGISTRY --docker-username=$GITHUB_USER \
            --docker-password=$GITHUB_TOKEN --docker-email=$K8S_DOCKER_EMAIL
    elif [[ -n "$QLIK_DOCKER_DEV_REGISTRY" ]] && [[ "$K8S_DOCKER_REGISTRY" == "$QLIK_DOCKER_DEV_REGISTRY" ]]; then
        # TODO: Remove this block when it is no longer used
        echo "====> Create secret for docker registry"
        kubectl create secret docker-registry --namespace $CHART_NAME $K8S_DOCKER_REGISTRY_SECRET \
            --docker-server=$K8S_DOCKER_REGISTRY --docker-username=$QLIK_DOCKER_DEV_USERNAME \
            --docker-password=$QLIK_DOCKER_DEV_PASSWORD --docker-email=$K8S_DOCKER_EMAIL
    else
        # TODO: Change the output in this block when the elif block is removed
        echo "QLIK_DOCKER_DEV_REGISTRY: ${QLIK_DOCKER_DEV_REGISTRY}"
        echo "K8S_DOCKER_REGISTRY: ${K8S_DOCKER_REGISTRY}"
        echo "Error: Unexpected value for QLIK_DOCKER_DEV_REGISTRY and/or K8S_DOCKER_REGISTRY"
        exit 1
    fi
fi

if [[ -n "$CUSTOM_ACTIONS" ]]; then
  echo "==> Running custom actions"
  echo "${CUSTOM_ACTIONS}"
  # Possibly, CUSTOM_ACTIONS is a singleline string created from a multiline string by substitution of special characters.
  # Here, we do the inverse operation, i.e. we "multilinearize" CUSTOM_ACTIONS, to make eval work.
  # For details, see https://renehernandez.io/snippets/multiline-strings-as-a-job-output-in-github-actions/.
  CUSTOM_ACTIONS="${CUSTOM_ACTIONS//'%25'/'%'}"
  CUSTOM_ACTIONS="${CUSTOM_ACTIONS//'%0A'/$'\n'}"
  CUSTOM_ACTIONS="${CUSTOM_ACTIONS//'%0D'/$'\r'}"
  eval "${CUSTOM_ACTIONS}"
fi

# Install a dependency chart (e.g. CRDs) before installing the main chart
if [[ -n "$INIT_CHART" ]]; then
  runthis "helm pull oci://ghcr.io/qlik-trial/helm/$INIT_CHART --version $INIT_CHART_VERSION"
  runthis "helm install init ${INIT_CHART}-${INIT_CHART_VERSION}.tgz"
fi

# Add any helm cli arguments when installing chart
if [[ -n "$EXTRA_HELM_CMD" ]]; then
  options+=("$EXTRA_HELM_CMD")
fi

# If tests/ci-values.yaml exits in the same folder as chart use that values file
if [[ -f "$CHART_DIR/tests/ci-values.yaml" ]]; then
  options+=(-f "${CHART_DIR}/tests/ci-values.yaml")
fi

# For CI testing, clustered nats-streaming is not required and this saves ~1 min of runner time
if [[ "${SINGLE_NATS_STREAMING:=true}" == "true" ]]; then
  options+=(-f "${SCRIPT_DIR}/helmvalues/messaging-non-clustered.yaml")
fi

runthis "helm install $CHART_NAME $CHART_NAME-$VERSION.tgz --namespace $CHART_NAME --create-namespace $EXTRA_HELM_CMD" "${options[@]}"

sleep 30
check_helm_deployment
