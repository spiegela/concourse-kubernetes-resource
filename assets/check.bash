#!/bin/bash

set -e
set -o pipefail

exec 3>&1 # make stdout available as fd 3 for the result
exec 1>&2 # redirect all output to stderr for logging

# Read inputs
PAYLOAD=$(cat <&0)

TRACING_ENABLED=$(jq -r '.source.tracing_enabled // empty' <<< "$PAYLOAD")
if [ "$TRACING_ENABLED" == "true" ]; then
  set -x
fi

COMPONENT=$(jq -r '.source.component // empty' <<< "$PAYLOAD")
if [ -z "$COMPONENT" ]; then
  echo "source.component field is required ⚠️"
  exit 1
fi

source /opt/resource/common.sh

COMPONENTS_DIR=$(setup_components_dir "$PAYLOAD")
COMPONENT_DIR="$COMPONENTS_DIR/components/$COMPONENT"
TAG=$(jq -r '.source.tag // empty' <<< "$PAYLOAD")
VERSION=$(jq -r '.source.version // empty' <<< "$PAYLOAD")

if [ ! -d  "$COMPONENT_DIR" ]; then
  >&3 echo "[]"
  rm -rf "$COMPONENTS_DIR"
  exit 0
fi

if [ -n "$TAG" ]; then
  pushd "$COMPONENTS_DIR"
    VERSION=$(./product get "$TAG" "$COMPONENT")
  popd
fi

if [ -n "$VERSION" ]; then
  if [ -d "$COMPONENT_DIR/$VERSION" ]; then
    echo "[{\"version\": \"$VERSION\"}]"
    rm -rf "$COMPONENTS_DIR"
    exit 0
  else
    echo "[]"
    rm -rf "$COMPONENTS_DIR"
    exit 0
  fi
fi

shopt -s extglob
shopt -s dotglob
shopt -s nullglob

VERSION_PATHS=("$COMPONENT_DIR/"!(tags))
if [ -z "${VERSION_PATHS[*]}" ]; then
    echo "[]"
    rm -rf "$COMPONENTS_DIR"
    exit 0
fi

VERSIONS=()
for VERSION_PATH in "${VERSION_PATHS[@]}" ; do
  VERSIONS+=( "$(basename "$VERSION_PATH")" )
done

VERSIONS_CSV=$(printf '{"version": "%s"}, ' "${VERSIONS[@]}" | sed -e 's|, $||')

>&3 echo "[$VERSIONS_CSV]"
rm -rf "$COMPONENTS_DIR"