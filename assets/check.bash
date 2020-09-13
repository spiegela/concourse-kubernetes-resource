#!/bin/bash

set -e
set -o pipefail

exec 3>&1 # make stdout available as fd 3 for the result
exec 1>&2 # redirect all output to stderr for logging

# Read inputs
PAYLOAD=$(cat <&0)

TRACING_ENABLED=$(jq -r '.source.tracing_enabled // empty' <<< "$PAYLOAD")
if [ "$TRACING_ENABLED" = "true" ]; then
  set -x
fi

source /opt/resource/common.sh

setup_kubernetes "$PAYLOAD"

ARGS=()
read -r -a ARGS <<< "$(base_args "$PAYLOAD" "CHECK")"

NOT_FOUND_REGEX="^Error[[:space:]]from[[:space:]]server[[:space:]](NotFound):"

# Allow command to fail, so we can check for NotFound errors
set +e
OBJECT_JSON=$(kubectl get "${ARGS[@]:1}" -o json 2> stderr.out)
set -e
STDERR=$(cat stderr.out)

# shellcheck disable=SC2181 # Capturing STDOUT & STDERR on a separate line is
# better than testing the exit code in-line
if [ $? -ne 0 ]; then
  if [[ "$STDERR" =~ $NOT_FOUND_REGEX ]]; then
    >&3 echo "[]"
    exit 0
  fi
  echo "$STDERR"
  exit 1
fi

>&3 echo "[$(object_versions "$OBJECT_JSON" "$TRACING_ENABLED")]"