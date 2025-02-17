#!/bin/bash -l
set -o pipefail

RELEASE_TAG="0"
BRANCH_NAME=""

# Unshallow git repository. Do not fail in case the repository is already unshallowed.
git fetch --prune --unshallow || true

echo "Setting _sha..."

# On push event
if [ "$GITHUB_EVENT_NAME" == "push" ]; then
    _sha=$GITHUB_SHA
    echo "_sha from push event: ${_sha}"
    echo "${GITHUB_REF}" | grep -E '^refs/heads/' && BRANCH_NAME=${GITHUB_REF##*/}
fi

# On pull_request event
if [ "$GITHUB_EVENT_NAME" == "pull_request" ]; then
    _sha=$(jq -r .pull_request.head.sha "$GITHUB_EVENT_PATH")
    echo "_sha from pull request: ${_sha}"
    BRANCH_NAME=${GITHUB_HEAD_REF}
fi

# fallback, if _sha isn't set, try to read from environment
_sha=${_sha:=$SHA}
echo "_sha: ${_sha}"

# git-describe - Give an object a human readable name based on an available ref
# On PR actions/checkout checkouts a merge commit instead of commit sha, git describe
# returns merge commit. To avoid this unpredictable commit sha, we will describe
# the actual commit
git_rev=$(git describe --tags --abbrev=7 ${_sha} --match "v[0-9]*.[0-9]*.[0-9]*")

# If git revision is not an exact semver tag, then bump patch
# An exact semver does not contain a '-'
if [[ "$git_rev" == *-* ]]; then
  # Transforms 0.0.0-0-g1234abc to 0.0.1-0.g123abc
  git_rev=$(echo $git_rev | perl -ne 'm/(^v\d+\.\d+\.)(\d+)(.*)(\-g)(.*$)/ && print $1 . int(1+$2) . $3 . ".g" . $5')
fi

# If no version is returned from git describe, generate one
[ -z "$git_rev" ] && git_rev="v0.0.0-0.g${_sha:0:7}"

# Return Version without v prefix
VERSION=${git_rev#v}

# On tag push that matches refs/tags/v*.*.*, use that version regardless of git describe
if echo "$GITHUB_REF" | grep -E 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$'; then
    VERSION=${GITHUB_REF#*/v}
    RELEASE_TAG="1"
fi

[ -z "$VERSION" ] && exit 1
echo "Set version: ${VERSION}"
echo "Set commit_sha: ${_sha}"
echo "Set branch_name: ${BRANCH_NAME}"

# Set GitHub Action environment and output variable
# VERSION
echo "VERSION=${VERSION}" >> $GITHUB_ENV
echo "VERSION=${VERSION}" >> $GITHUB_OUTPUT

# COMMIT_SHA
echo "COMMIT_SHA=${_sha}" >> $GITHUB_ENV
echo "COMMIT_SHA=${_sha}" >> $GITHUB_OUTPUT

# BRANCH_NAME
echo "BRANCH_NAME=${BRANCH_NAME}" >> $GITHUB_ENV
echo "BRANCH_NAME=${BRANCH_NAME}" >> $GITHUB_OUTPUT

# RELEASE TAG
echo "RELEASE_TAG=${RELEASE_TAG}" >> $GITHUB_ENV
echo "RELEASE_TAG=${RELEASE_TAG}" >> $GITHUB_OUTPUT
