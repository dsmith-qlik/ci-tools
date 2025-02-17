# action-helm-tools

GitHub Action for packaging, testing helm charts and publishing to Artifactory helm repo

_Note this action is written to specifically work with Helm repos in Artifactory_

## Optional input

`action` - `[package, test, publish]`

- Leave empty to run `package, test and publish`
- `package` - Involves helm client only and does dependency build, lint and package chart
- `test` - Creates K8s cluster (in Docker), sets up helm, install chart in a namespace and waits for all pods to be up and running
- `publish` - Uses jfrog cli to check for existing package with same version and uploads if new chart is built
- `package_and_test` - Run `package` and `test` in one step
- `package_and_publish` - Run `package` and `publish`, skipping `test` for images that cannot start on their own

## Version

`VERSION` set as environment variable is required

## Failed pod logs/describe

If a pod fails the logs and its describe will be put on directory `${GITHUB_WORKSPACE}/podlogs`.

Logs are printed in the console but can be saved as artifacts. Use `$POD_LOGS` environment variable or `${{ env.POD_LOGS }}` to get the directory where logs are stored. `actions/upload-artifact` can be used to save artifacts, see example in Example workflows.

## Install values files

If action finds `manifests/chart/<chart-name>/tests/ci-values.yaml` file it will automatically use it in Github actions to deploy test chart.

To add `ci-values.yaml`

- Create `ci-values.yaml` file in `manifests/chart/<chart-name>/tests` and add values that enables the chart to deploy
- Add `tests/` in `.helmignore` file

### Use action-version to set VERSION variable

```yaml
steps:
  - uses: actions/checkout@v2
  - uses: qlik-oss/ci-tools/action-version@master
```

## Required Environment variables

```yaml
ARTIFACTORY_USERNAME: ${{ secrets.ARTIFACTORY_USERNAME }} # ARTIFACTORY_USERNAME (Artifactory username) must be set in GitHub Repo secrets
ARTIFACTORY_PASSWORD: ${{ secrets.ARTIFACTORY_PASSWORD }} # ARTIFACTORY_PASSWORD (Artifactory api key) must be set in GitHub Repo secrets
```

## Optional Environment (override) variables

```yaml
GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} # See NOTE below
DEPENDENCY_UPDATE: "true|false" # REQUIRES GITHUB_TOKEN; Check for chart dependency updates and create PR with updates.
CHART_NAME: mycomponent # Chart name
CHART_DIR: manifests/charts/mycomponent # Chart path
EXTRA_HELM_CMD: # Extra helm command(s) (set or -f myValues.yaml) to use when installing chart in K8s cluster
HELM_REPO: # Artifactory helm repository to push chart to
HELM_LOCAL_REPO: # `helm repo add <name>` Artifactory helm chart repo name for pulling dependencies
HELM_VIRTUAL_REPO: # Artifactory virtual helm repo that holds dependencies
HELM_VERSION: # Override helm version. Default "2.14.3"
K8S_DOCKER_EMAIL: xyx@tld.com # Docker email to use when creating k8s docker secret
K8S_DOCKER_REGISTRY: xyz-docker.jfrog.io # Artifactory docker registry (as specified in chart image.registry)
K8S_DOCKER_REGISTRY_SECRET: xyz-docker-secret # Artifactory pull secret (as specified in chart image.pullSecrets)
KUBECTL_VERSION: # Override kubectl version. Default "1.15.4"
KIND_VERSION: Override KIND version. Default version - look in common.sh
KIND_IMAGE: Override KIND image (K8s version). Default version - look in common.sh
DEPLOY_TIMEOUT: # Timeout on waiting for pods to get to running state. Default 300 seconds
INIT_CHART: repo/chartName # If another chart's deployment is required prior to deploying the packaged chart
INIT_CHART_VERSION: n.m.o # Explicit init chart version, required if INIT_CHART is given
IMAGE_TAG_UPDATE: "true|false" # DEFAULT true; Update image.tag based on VERSION env variable
CUSTOM_ACTIONS: # During test phase, run shell commands before deploying the chart. See CUSTOM_ACTIONS below for examples.
SINGLE_NATS_STREAMING: "true|flase" # DEFAULT true; Do not deploy clustered nats-streaming when testing chart
```

**NOTE** If the action is used on a `workflow_dispatch`, the commit status (check) is not set automatically when workflow is ran. To set commit status, add the following environment variable:

```yaml
uses: qlik-oss/ci-tools/action-helm-tools@master
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Example workflow

The simplest workflow for packaging, testing and publishing a chart

```yaml
name: Helm lint, test, package and publish

on: pull_request

env:
  ARTIFACTORY_USERNAME: ${{ secrets.ARTIFACTORY_USERNAME }}
  ARTIFACTORY_PASSWORD: ${{ secrets.ARTIFACTORY_PASSWORD }}

jobs:
  helm-suite:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - uses: qlik-oss/ci-tools/action-version@master

    - name: Package & Test Helm chart
      uses: qlik-oss/ci-tools/action-helm-tools@master

    # Optional
    - uses: actions/upload-artifact@v2
      if: failure()
      with:
        name: pod_logs
        path: ${{ env.POD_LOGS }}
```

Run package and test separate from publish, if a step in between is desired.

```yaml
name: Helm lint, test, package and publish

on: pull_request

env:
  ARTIFACTORY_USERNAME: ${{ secrets.ARTIFACTORY_USERNAME }}
  ARTIFACTORY_PASSWORD: ${{ secrets.ARTIFACTORY_PASSWORD }}
  EXTRA_HELM_CMD: "-f ${CHART_DIR}/tests/myValues.yaml"

jobs:
  helm-suite:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - uses: qlik-oss/ci-tools/action-version@master

    - name: Package & Test Helm chart
      uses: qlik-oss/ci-tools/action-helm-tools@master
      with:
        action: "package_and_test"

    # - name: myOtherJob1
    #   run: Some tests against deployed chart

    - name: Publish Helm chart
      uses: qlik-oss/ci-tools/action-helm-tools@master
      with:
        action: "publish"
```

## CUSTOM_ACTIONS

Run one or more commands after K8s (KIND) cluster is up and before deploying the chart, for example if some or multiple prerequisites are required for the chart to come up healthy.

The commands are run after the Chart is packaged and K8s cluster is created, and before the main chart is installed and tested.

``` yaml
    - name: Package & Test Helm chart
      uses: qlik-oss/ci-tools/action-helm-tools@master
      env:
        CUSTOM_ACTIONS: |
          helm install some/chart
          kubectl create clusterrolebinding
          kubectl patch ...
          ...
```
