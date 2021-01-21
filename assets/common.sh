#!/bin/bash
set -e

# setup_components_dir prepares the container for usage as a "check", "get", or "put" operation,
# parsing the source block, cloning the component repository, and setting up git. It returns the
# location of the components directory to be used in individual operations
setup_components_dir() {
  local PAYLOAD=$1 URI PRIVATE_KEY BRANCH COMPONENTS_DIR

  URI=$(jq -r '.source.uri // empty' <<< "$PAYLOAD")
  if [ -z "$URI" ]; then
      >&2 echo "source.uri field is required ⚠️"
      exit 1
  fi

  PRIVATE_KEY=$(jq -r '.source.private_key // empty' <<< "$PAYLOAD")
  if [ -z "$PRIVATE_KEY" ]; then
      >&2 echo "source.private_key field is required ⚠️"
      exit 1
  fi

  BRANCH=$(jq -r '.source.branch // "master"' <<< "$PAYLOAD")

  >&2 echo "Setting up SSH credentials 🔐"
  mkdir -p ~/.ssh
  ssh-keyscan eos2git.cec.lab.emc.com >> ~/.ssh/known_hosts
  echo -e "${PRIVATE_KEY//_/\\n}" > ~/.ssh/id_rsa
  chmod og-rwx ~/.ssh/id_rsa

  >&2 echo "Cloning component versions repository ⬇️"
  COMPONENTS_DIR=$(mktemp -p /tmp -d components.XXXXXX)
  >&2 git clone "$URI" "$COMPONENTS_DIR"
  >&2 pushd "$COMPONENTS_DIR"
    >&2 git checkout "$BRANCH"
  >&2 popd
  echo -n "$COMPONENTS_DIR"
}

component_version_data() {
  local PAYLOAD=$1 COMPONENT=$2 VERSION=$3 URI PROJECT

  URI=$(jq -r '.source.uri // empty' <<< "$PAYLOAD")
  if [ -z "$URI" ]; then
      >&2 echo "source.uri field is required ⚠️"
      exit 1
  fi

  BRANCH=$(jq -r '.source.branch // "master"' <<< "$PAYLOAD")
  PROJECT=$(awk -F'[@/:]' '$1 == "git" {print $3} $1 == "https" {print $5}' <<<"$URI")
  if [ -z "$PROJECT" ]; then
      >&2 echo "unable to detect project name from URI: $URI"
      exit 1
  fi

  echo -n "{\"version\": {\"version\": \"${VERSION}\"}, \"metadata\": ["
  echo -n "{\"name\": \"component\", \"value\": \"$COMPONENT\"},"
  echo -n "{\"name\": \"version\", \"value\": \"$VERSION\"},"
  echo -n "{\"name\": \"link\", \"value\": \"https://eos2git.cec.lab.emc.com/$PROJECT/component-versions/tree/$BRANCH/components/$COMPONENT/$VERSION\"}"
  echo "]}"
}