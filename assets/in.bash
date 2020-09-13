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

setup_kubernetes "$PAYLOAD" "$SOURCE"

ARGS=()
read -r -a ARGS <<< "$(base_args "$PAYLOAD" "IN")"

OUTPUT_ARGS=()
read -r -a OUTPUT_ARGS <<< "$(output_args "$PAYLOAD")"
OUTPUT_FILE=$(output_file "$PAYLOAD" "$SOURCE")

WAIT=$(jq -r '.params.wait // empty' <<< "$PAYLOAD")
WAIT_FOR=$(jq -r '.params.wait_for // empty' <<< "$PAYLOAD")

ALL_READY=1

if [ "$WAIT" == "true" ]; then
  if [ -z "$WAIT_FOR" ]; then
    echo "⚠️ \"wait_for\" parameter is not supplied.  It is required for waiting on resources with in \"get\" blocks."
  fi

  echo "⏳ Waiting for resources to match desired status conditions:"
  echo "    ▶️ kubectl get ${ARGS[*:1]} -o jsonpath=\"$WAIT_FOR\""
  TIMEOUT=$(jq -r '.params.timeout // 30' <<< "$PAYLOAD")

  for (( i = 0; i < TIMEOUT; i++ )); do
    read -r -a STATES <<< "$(kubectl get "${ARGS[@]:1}" -o jsonpath="$WAIT_FOR")"
    for STATE in "${STATES[@]}" ; do
      if [ "$STATE" == "False" ]; then
        ALL_READY=0
        break
      fi
    done
    sleep 1
  done
fi

# Copy arguments to new array to add command arguments, which are only used for
# the primary command execution, not wait or version queries
#EXEC_ARGS=("${ARGS[@]}")
#
#COMMAND_ARGS=()
#read -r -a COMMAND_ARGS <<< "$(jq -r '.params.command_args // empty' <<< "$PAYLOAD")"
#if [ -n "${COMMAND_ARGS[*]}" ]; then
#  EXEC_ARGS+=("${COMMAND_ARGS[@]}")
#fi

if [ $ALL_READY -eq 1 ]; then
  echo "🔎 Performing a Kubernetes query:"
  echo "    ▶️ kubectl ${ARGS[*]} ${OUTPUT_ARGS[*]} > $OUTPUT_FILE"
  if [ "$TRACING_ENABLED" == "true" ]; then
    kubectl "${ARGS[@]}" "${OUTPUT_ARGS[@]}" | tee "$OUTPUT_FILE"
  else
    kubectl "${ARGS[@]}" "${OUTPUT_ARGS[@]}" > "$OUTPUT_FILE"
  fi
else
  echo "💩 Timed out waiting for resources to reach desired status condition"
  exit 1
fi

OBJECT_JSON=$(kubectl get "${ARGS[@]:1}" -o json)
>&3 object_version_data "$OBJECT_JSON" "$TRACING_ENABLED"