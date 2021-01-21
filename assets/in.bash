#!/bin/bash

set -e
set -o pipefail

exec 3>&1 # make stdout available as fd 3 for the result
exec 1>&2 # redirect all output to stderr for logging

source /opt/resource/common.sh

SOURCE=$1
PAYLOAD=$(cat <&0)

TRACING_ENABLED=$(jq -r '.source.tracing_enabled // empty' <<< "$PAYLOAD")
if [ "$TRACING_ENABLED" = "true" ]; then
  set -x
fi

source /opt/resource/common.sh

COMPONENTS_DIR=$(setup_components_dir "$PAYLOAD")
PRODUCT_BIN="$COMPONENTS_DIR/product"

COMPONENT=$(jq -r '.source.component // empty' <<< "$PAYLOAD")
if [ -z "$COMPONENT" ]; then
  echo "source.component field is required ⚠️"
  exit 1
fi

# Allow version field specified in params to override that defined in source
# if neither is specified, version will remain empty, and tag will be used
VERSION=$(jq -r '.params.version // empty' <<< "$PAYLOAD")
if [ -z "$VERSION" ]; then
  VERSION=$(jq -r '.source.version // empty' <<< "$PAYLOAD")
fi

# If no version is specified, then we will retrieve the version from the tag
if [ -z "$VERSION" ]; then

  # Allow tag field specified in params to override that defined in source
  # if neither is specified, "latest" tag will be assumed
  TAG=$(jq -r '.params.tag // empty' <<< "$PAYLOAD")
  if [ -z "$TAG" ]; then
    TAG=$(jq -r '.source.tag // empty' <<< "$PAYLOAD")
    if [ -z "$TAG" ]; then
      TAG="latest"
    fi
  fi

  pushd "$COMPONENTS_DIR"
    VERSION=$("$PRODUCT_BIN" get "$TAG" "$COMPONENT")
    if [ -z "$VERSION" ]; then
      echo "$COMPONENT tag $TAG is not found"
      exit 1
    fi
  popd
fi

VERSION_DIR="$COMPONENTS_DIR/components/$COMPONENT/$VERSION"

if [ ! -d "$VERSION_DIR" ]; then
  echo "$COMPONENT version $VERSION not found ⚠️"
  exit 1
fi
cp "$VERSION_DIR/"* "$SOURCE"

CLONE_SOURCES=$(jq -r '.params.clone_sources // empty' <<< "$PAYLOAD")

# write component metadata to source directory
echo "$VERSION" > "$SOURCE/version"
echo "$COMPONENT" > "$SOURCE/component"
sed -re 's|^v||' <<<"$VERSION" > "$SOURCE/tag"
sed -re 's|[.@_:<>=+-]+|-|g' <<<"$VERSION" > "$SOURCE/slug"

mkdir "$SOURCE/buildRepos"

SOURCES=()
read -r -a SOURCES <<< "$(jq -r '.buildRepos[] | .url + "|" + .commit' < "$VERSION_DIR/artifacts.json")"

for SOURCE_STRING in "${SOURCES[@]}" ; do
  URL=$(cut -d"|" -f1 <<< "$SOURCE_STRING")
  COMMIT=$(cut -d"|" -f2 <<< "$SOURCE_STRING")
  REPO_FLATTENED=$(sed -e 's/\//_/g' <<< "$URL")

  echo "$COMMIT" > "$SOURCE/buildRepos/$REPO_FLATTENED"

  if [ "$CLONE_SOURCES" == "true" ]; then
    mkdir -p "$SOURCE/sources"
    git clone "$URL" "$SOURCE/sources/$REPO_FLATTENED"
    pushd "$SOURCE/sources/$REPO_FLATTENED"
      git checkout "$COMMIT"
    popd
  fi
done

>&3 component_version_data "$PAYLOAD" "$COMPONENT" "$VERSION"
