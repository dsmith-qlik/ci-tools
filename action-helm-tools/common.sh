#!/bin/bash -l
set -eo pipefail

# Defaults
export HELM_REPO=${HELM_REPO:="helm-dev"}
export HELM_VIRTUAL_REPO=${HELM_VIRTUAL_REPO:="qlikhelm"}
export HELM_LOCAL_REPO=${HELM_LOCAL_REPO:="qlik"}
export K8S_DOCKER_EMAIL=${K8S_DOCKER_EMAIL:="xyz@example.com"}
export DEPENDENCY_UPDATE=${DEPENDENCY_UPDATE:="false"}

export DOCKER_DEV_REGISTRY="ghcr.io/qlik-trial"
export HELM_DEV_REGISTRY="ghcr.io/qlik-trial/helm"

# Tools
export HELM_VERSION=${HELM_VERSION:="3.10.2"}
export KUBECTL_VERSION=${KUBECTL_VERSION:="1.24.15"}
export KIND_VERSION=${KIND_VERSION:="v0.20.0"}
# Get Image version from https://github.com/kubernetes-sigs/kind/releases, look for K8s version in the release notes
export KIND_IMAGE=${KIND_IMAGE:="kindest/node:v1.24.15@sha256:7db4f8bea3e14b82d12e044e25e34bd53754b7f2b0e9d56df21774e6f66a70ab"}
export YQ_VERSION="4.25.2"

get_component_properties() {
    install_yq

    # Get chart name
    export CHART_NAME
    if [ -z "$CHART_NAME" ]; then
        CHART_NAME=$(yq e '.publishedPackages.helm.ids[0]' component.yaml)
        if [[ "$CHART_NAME" == "null" ]]; then
            CHART_NAME=$(yq e '.componentId' component.yaml)  # Default is componentId
        fi
        if [[ "$CHART_NAME" == "null" ]]; then
            echo "::error file=component.yaml::Cannot get chart name from component.yaml"
            exit 1
        fi
    fi

    # Get chart dir
    export CHART_DIR
    if [ -z "$CHART_DIR" ]; then
      if [ -d "manifests/chart/${CHART_NAME}" ]; then
        CHART_DIR="manifests/chart/${CHART_NAME}"
      elif [ -d "manifests/${CHART_NAME}/chart/${CHART_NAME}" ]; then
        CHART_DIR="manifests/${CHART_NAME}/chart/${CHART_NAME}"
      else
        echo "::error ::Cannot get chart dir"
        exit 1
      fi
    fi

    # Get K8S registry pull secret name and registry
    export K8S_DOCKER_REGISTRY_SECRET
    if [ -z "$K8S_DOCKER_REGISTRY_SECRET" ]; then
        K8S_DOCKER_REGISTRY_SECRET=$(yq e '.image.pullSecrets[0].name' "${CHART_DIR}/values.yaml")
        [ "$K8S_DOCKER_REGISTRY_SECRET" = "null" ] && K8S_DOCKER_REGISTRY_SECRET=$(yq e '.imagePullSecrets[0].name' "${CHART_DIR}/values.yaml")
    fi

    export K8S_DOCKER_REGISTRY
    if [ -z "$K8S_DOCKER_REGISTRY" ]; then
        echo "CHART_DIR: ${CHART_DIR}"
        echo "------- values.yaml start -------"
        cat ${CHART_DIR}/values.yaml
        echo "------- values.yaml end -------"
        K8S_DOCKER_REGISTRY=$(yq e '.image.registry' "${CHART_DIR}/values.yaml")
        if [ "$K8S_DOCKER_REGISTRY" = "null" ]; then
            echo "::error file=${CHART_DIR}/values.yaml::Cannot get image.registry from values.yaml"
            exit 1
        fi
    fi

    export CHART_APIVERSION
    CHART_APIVERSION="$(helm inspect chart "$CHART_DIR" | yq e '.apiVersion' -)"
}

install_kubectl() {
    echo "==> Get kubectl:${KUBECTL_VERSION}"
    curl -LsO https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
}

get_helm() {
    echo "==> Get helm:${HELM_VERSION}"
    curl -Ls "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | tar xvz
    chmod +x linux-amd64/helm
    sudo mv linux-amd64/helm /usr/local/bin/helm
}

install_helm() {
    if ! command -v helm; then
        echo "Helm is missing"
        get_helm
    elif ! [[ $(helm version --short -c) == *${HELM_VERSION}* ]]; then
        echo "Helm $(helm version --short -c) is not desired version"
        get_helm
    fi
}

add_helm_repos() {
  install_helm
  get_component_properties

  public_repos=(
    "bitnami https://charts.bitnami.com/bitnami"
    "bitnami-pre-2022 https://raw.githubusercontent.com/bitnami/charts/eb5f9a9513d987b519f0ecd732e7031241c50328/bitnami"
    "dandydev https://dandydeveloper.github.io/charts"
    "stable https://charts.helm.sh/stable"
    "ingress-nginx https://kubernetes.github.io/ingress-nginx"
    "grafana https://grafana.github.io/helm-charts"
    "prometheus-community https://prometheus-community.github.io/helm-charts"
    "connaisseur https://sse-secure-systems.github.io/connaisseur/charts"
    "infracloudio https://infracloudio.github.io/charts"
    "datadog https://helm.datadoghq.com/"
    "jetstack  https://charts.jetstack.io"
    "twin https://twin.github.io/helm-charts"
    "argo https://argoproj.github.io/argo-helm"
    "dynatrace https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/master/config/helm/repos/stable"
    "botkube https://charts.botkube.io"
    "karpenter https://charts.karpenter.sh"
    "teleport https://charts.releases.teleport.dev"
    "opensearch-project https://opensearch-project.github.io/helm-charts"
    "aws-eks https://aws.github.io/eks-charts"
    "uswitch https://uswitch.github.io/kiam-helm-charts/charts"
  )
  # "kubed https://charts.appscode.com/stable/"
  # charts.appscode.com currently not working, get builds working angain and figure out what breaks because kubed is missing instead

  echo "==> Helm add repo"
  if [[ -n "$GITHUB_USER" ]] && [[ -n "$GITHUB_TOKEN" ]]; then
    echo "==> Helm registry login (registry is $HELM_DEV_REGISTRY)"
    echo $GITHUB_TOKEN | helm registry login --username $GITHUB_USER --password-stdin https://$HELM_DEV_REGISTRY
  elif [ -n "$QLIK_HELM_DEV_REGISTRY" ]; then
    # TODO: Remove this block when it is no longer used
    echo "==> Helm registry login"
    echo $QLIK_HELM_DEV_PASSWORD | helm registry login --username $QLIK_HELM_DEV_USERNAME --password-stdin https://$QLIK_HELM_DEV_REGISTRY
  fi

  for repo in "${public_repos[@]}"; do
    IFS=" " read -r -a arr <<< "${repo}"
      helm repo add "${arr[0]}" "${arr[1]}"
  done
  helm repo update
}

check_helm_deployment() {
    echo "==> Check helm deployment"
    DEPLOY_TIMEOUT=${DEPLOY_TIMEOUT:-300}
    "$SCRIPT_DIR/helm-deployment-check.sh" --release $CHART_NAME --namespace $CHART_NAME -t $DEPLOY_TIMEOUT
}

install_jfrog() {
    if ! command -v jfrog; then
        echo "==> Installing jfrog cli"
        curl -fL https://getcli.jfrog.io | sh
        chmod +x ./jfrog
        sudo mv ./jfrog /usr/local/bin/jfrog
    fi
}

setup_kind_internal() {
    echo "==> Setting up KIND (Kubernetes in Docker)"

    if ! command -v kind; then
        echo "==> Get KIND:${KIND_VERSION}"
        curl -Lso ./kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
    fi

    clusters=$(kind get clusters -q)

    if [ -z "$clusters" ]; then
        kind create cluster --image ${KIND_IMAGE} --name ${CHART_NAME}
    else
        echo "KIND cluster already exist, continue"
    fi
}

setup_kind() {
  export -f setup_kind_internal
  timeout 180s bash -c setup_kind_internal || EXITCODE=$?
  if [ $EXITCODE != 0 ]; then
      echo "::error ::Kubernetes (in Docker) setup timed out. Usually intermittent, re-run the job to try again"
      exit 1
  fi
}

yaml_lint() {
    echo "==> YAML lint"
    if ! command -v yamllint; then
        sudo pip install yamllint
    fi

    yamllint -c "$SCRIPT_DIR/default.yamllint" $CHART_DIR -f parsable
}

install_yq() {
    if ! command -v yq || [[ $(yq --version 2>&1 | cut -d ' ' -f3) != "${YQ_VERSION}" ]] ; then
        echo "==> Get yq:${YQ_VERSION}"
        sudo curl -Ls https://github.com/mikefarah/yq/releases/download/v$YQ_VERSION/yq_linux_amd64 -o /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
    fi
}

runthis() {
    echo "$@"
    eval "$@"
}
