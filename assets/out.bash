#!/bin/bash

set -e
set -o pipefail

exec 3>&1 # make stdout available as fd 3 for the result
exec 1>&2 # redirect all output to stderr for logging

trap "exit 1" TERM
export PID=$$

source /opt/resource/common.sh

SOURCE=$1
PAYLOAD=$(cat <&0)

TRACING_ENABLED=$(jq -r '.source.tracing_enabled' <<< "$PAYLOAD")
if [ "$TRACING_ENABLED" = "true" ]; then
  set -x
fi

setup_kubernetes "$PAYLOAD" "$SOURCE"

ARGS=()
read -r -a ARGS <<< "$(base_args "$PAYLOAD" "OUT")"

OUTPUT_ARGS=()
read -r -a OUTPUT_ARGS <<< "$(output_args "$PAYLOAD")"
OUTPUT_FILE=$(output_file "$PAYLOAD" "$SOURCE")

COMMAND_ARGS=()
read -r -a COMMAND_ARGS <<< "$(jq -r '.params.command_args // empty' <<< "$PAYLOAD")"

# Execution arguments are held separate from others, since they apply only to
# the primary command execution, not wait or version queries
EXEC_ARGS=()
if [[ "${ARGS[1]}" == "-f" || "${ARGS[1]}" =~ ^[A-z]+$ ]]; then
  # resource uses a template, or list kind.  Command arguments can be placed at the end
  EXEC_ARGS=("${ARGS[@]}" "${COMMAND_ARGS[@]}")
elif [[ "${ARGS[1]}" =~ ^[A-z]+\/.* ]]; then
  # resource uses a one or more kind/name objects, command arguments must be
  # spliced between kind and name
  if [[ "${ARGS[2]}" =~ ^[:alpha:]\/.* ]]; then
    echo "⚠️ Error: multiple objects in \"put\" operation require a file/url parameter."
    exit 1
  fi
  KIND=$(echo "${ARGS[1]}" | cut -d"/" -f1 | tr "[:upper:]" "[:lower:]")
  NAME=$(echo "${ARGS[1]}" | cut -d"/" -f2)
  EXEC_ARGS=("${ARGS[0]}" "$KIND" $(echo "${COMMAND_ARGS[@]}") "$NAME" $(echo "${ARGS[@]:2}"))
else
  echo "⚠️ Error: unable to determine resource format.  Must be a bug🐛. 😥"
  exit 1
fi

WAIT=$(jq -r '.params.wait // empty' <<< "$PAYLOAD")

if [ "${ARGS[0]}" == "delete" ]; then
  if [ "$WAIT" == "true"  ]; then
    EXEC_ARGS+=("--wait")
  fi
  echo "💀 Deleting kubernetes object(s)"
  echo "    ▶️ kubectl ${EXEC_ARGS[*]} ${OUTPUT_ARGS[*]} > $OUTPUT_FILE"

  if [ "$TRACING_ENABLED" == "true" ]; then
    kubectl "${EXEC_ARGS[@]}" "${OUTPUT_ARGS[@]}" | tee "$OUTPUT_FILE"
  else
    kubectl "${EXEC_ARGS[@]}" "${OUTPUT_ARGS[@]}" > "$OUTPUT_FILE"
  fi

  exit 0
fi

echo "🚀 Applying kubernetes object(s)"
echo "    ▶️ kubectl ${EXEC_ARGS[*]} ${OUTPUT_ARGS[*]} > $OUTPUT_FILE"
if [ "$TRACING_ENABLED" == "true" ]; then
  kubectl "${EXEC_ARGS[@]}" "${OUTPUT_ARGS[@]}" | tee "$OUTPUT_FILE"
else
  kubectl "${EXEC_ARGS[@]}" "${OUTPUT_ARGS[@]}" > "$OUTPUT_FILE"
fi

if [ "$WAIT" == "true"  ]; then
  WAIT_FOR=$(jq -r '.params.wait_for // "condition=available"' <<< "$PAYLOAD")
  TIMEOUT=$(jq -r '.params.timeout // 30' <<< "$PAYLOAD")

  echo "⏳ Waiting for object(s) to reach state: $WAIT_FOR"
  echo "    ▶️ kubectl wait --for=${WAIT_FOR}" --timeout="${TIMEOUT}"s "${ARGS[@]:1}"
  kubectl wait --for="${WAIT_FOR}" --timeout="${TIMEOUT}"s "${ARGS[@]:1}"
fi

OBJECT_JSON=$(kubectl get "${ARGS[@]:1}" -o json)
>&3 object_version_data "$OBJECT_JSON" "$TRACING_ENABLED"