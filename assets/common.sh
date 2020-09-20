#!/bin/bash
set -e

# object_queries converts a JSON payload into kind/name pairs used in.bash commands
object_queries() {
  jq -r '.source.objects | map(.kind + "/" + .name) | join(" ")' <<< "$1"
}

# output_args returns the output redirection arguments for the kubectl command
# these are separated from other arguments, because it is only used for the primary
# query.  Additional queries (for version printing, waiting, etc.) use the base
# arguments, but not the output arguments.
output_args() {
  local PAYLOAD=$1

  local TRACING_ENABLED
  TRACING_ENABLED=$(jq -r '.source.tracing_enabled // empty' <<< "$PAYLOAD")
  if [ "$TRACING_ENABLED" == "true" ]; then
      set -x
  fi

  local OUTPUT OUTPUT_FILE
  OUTPUT=$(jq -r '.params.output // empty' <<< "$PAYLOAD")
  OUTPUT_FILE=$(jq -r '.params.output_file // empty' <<< "$PAYLOAD")

  if [ -n "$OUTPUT" ]; then
    echo "-o $OUTPUT"
  fi
}

output_file() {
  local PAYLOAD=$1 SOURCE=$2

  OUTPUT=$(jq -r '.params.output // empty' <<< "$PAYLOAD")
  OUTPUT_FILE=$(jq -r '.params.output_file // empty' <<< "$PAYLOAD")

  if [ -z "$OUTPUT_FILE" ]; then
    EXTENSION=$(outfile_extension "$OUTPUT")
    OUTPUT_FILE="objects.$EXTENSION"
  fi
  echo "$SOURCE/$OUTPUT_FILE"
}

# base_command returns the base command command sent to kubectl for the operation.
base_command() {
  local PAYLOAD=$1 OPERATION=$2

  local TRACING_ENABLED
  TRACING_ENABLED=$(jq -r '.source.tracing_enabled // empty' <<< "$PAYLOAD")
  if [ "$TRACING_ENABLED" == "true" ]; then
      set -x
  fi

  local DELETE COMMAND
  DELETE=$(jq -r '.params.delete // "false"' <<< "$PAYLOAD")
  COMMAND=$(jq -r '.params.command // empty' <<< "$PAYLOAD")

  if [[ "$OPERATION" == "IN" || "$OPERATION" == "CHECK" ]]; then
    COMMAND=$(read_command "$COMMAND")
  elif [[ "$OPERATION" == "OUT" ]]; then
    if [[ "$DELETE" == "true" ]]; then
      COMMAND="delete"
    else
      COMMAND=$(write_command "$COMMAND")
    fi
  else
    >&2 echo "⚠️ Error: unsupported operation: $OPERATION"
    kill -s TERM "$PID"
  fi
  echo "$COMMAND"
}

read_command() {
  local COMMAND=$1
  WRITE_COMMANDS=(create expose set edit delete rollout scale autoscale certificate cordon uncordon drain taint port-forward cp apply patch replace convert config)
  if [ -z "$COMMAND" ]; then
      echo "get"
  elif [[ " ${WRITE_COMMANDS[*]} " =~ ${COMMAND} ]]; then
    >&2 echo "⚠️ Error: specified command: \"$COMMAND\" mutates an object, so should be used in a \"put\" operation"
    kill -s TERM "$PID"
  else
    echo "$COMMAND"
  fi
}

write_command() {
  local COMMAND=$1
  READ_COMMANDS=(explain get cluster-info top describe logs attach exec proxy auth diff kustomize completion api-resources api-versions version)
  if [ -z "$COMMAND" ]; then
      echo "apply"
  elif [[ " ${READ_COMMANDS[*]} " =~ ${COMMAND} ]]; then
    >&2 echo "⚠️ Error: specified command: \"$COMMAND\" does not mutate an object, so should be used in a \"get\" operation"
    kill -s TERM "$PID"
  else
    echo "$COMMAND"
  fi
}

# command_description returns a human readable description of the command operation
# to be performed for pretty output printing.
command_description() {
  local COMMAND=$1
  if [ "$COMMAND" == "get" ]; then
    echo "query"
  elif [ "$COMMAND" == "describe" ]; then
    echo "description"
  elif [ "$COMMAND" == "apply" ]; then
    echo "application"
  elif [ "$COMMAND" == "create" ]; then
    echo "creation"
  elif [ "$COMMAND" == "annotate" ]; then
    echo "annotation"
  elif [ "$COMMAND" == "update" ]; then
    echo "update"
  elif [ "$COMMAND" == "patch" ]; then
    echo "patching"
  else
    echo "operation"
  fi
}

# base_args will parse the resource payload to derive the "base" kubectl arguments
# including the command and flags.
base_args() {
  local PAYLOAD=$1 OPERATION=$2

  local TRACING_ENABLED
  TRACING_ENABLED=$(jq -r '.source.tracing_enabled // empty' <<< "$PAYLOAD")
  if [ "$TRACING_ENABLED" == "true" ]; then
      set -x
  fi

  local LIST_KIND
  LIST_KIND=$(jq -r '.source.list // empty' <<< "$PAYLOAD")

  local FILE
  FILE="$(jq -r '.params.file // empty' <<< "$PAYLOAD")"

  local SOURCE_URL
  SOURCE_URL=$(jq -r '.source.url // empty' <<< "$PAYLOAD")

  local PARAMS_URL
  PARAMS_URL=$(jq -r '.params.url // empty' <<< "$PAYLOAD")

  local OBJECTS=()
  read -r -a OBJECTS <<< "$(object_queries "$PAYLOAD")"

  local ARGS=()
  read -r -a ARGS <<< "$(base_command "$PAYLOAD" "$OPERATION")"

  local DESCRIPTION
  DESCRIPTION=$(command_description "${ARGS[0]}")

  if [ -f "$SOURCE/$FILE" ]; then
    >&2 echo "📄 Using file: \"$SOURCE/$FILE\" for object $DESCRIPTION"
    ARGS+=("-f" "$SOURCE/$FILE")
  elif [ -n "$PARAMS_URL" ]; then
    >&2 echo "🔗 Using url: \"$PARAMS_URL\" for object $DESCRIPTION"
    ARGS+=("-f" "$PARAMS_URL")
  elif [ -n "${SOURCE_URL}" ]; then
    >&2 echo "🔗 Using url: \"$SOURCE_URL\" for object $DESCRIPTION"
    ARGS+=("-f" "$SOURCE_URL")
  elif [ -n "$LIST_KIND" ]; then
    >&2 echo "📖 Using dynamic list for object queries"
    read -r -a LIST_FLAGS <<< "$(list_flags "$PAYLOAD")"
    ARGS+=("$LIST_KIND" "${LIST_FLAGS[@]}")
  elif [ -n "${OBJECTS[*]}" ]; then
    >&2 echo "🏷 No file specified or does not exist, using object names for $DESCRIPTION"
    ARGS+=("${OBJECTS[@]}")
  else
    >&2 echo "⚠️ Error: resource source or query is not configured with: objects, url, file, list, command arguments, or command"
    kill -s TERM "$PID"
  fi

  local NAMESPACE
  NAMESPACE=$(jq -r '.source.namespace // empty' <<< "$PAYLOAD")
  if [ -n "$NAMESPACE" ]; then
    ARGS+=("-n" "$NAMESPACE")
  fi

  echo "${ARGS[*]}"
}

# list_flags extracts the command line flags used for list queries from the JSON payload
list_flags() {
  local PAYLOAD=$1

  local TRACING_ENABLED
  TRACING_ENABLED=$(jq -r '.source.tracing_enabled // empty' <<< "$PAYLOAD")
  if [ "$TRACING_ENABLED" == "true" ]; then
      set -x
  fi

  local LABEL_SELECTOR FIELD_SELECTOR FLAGS=()
  LABEL_SELECTOR=$(jq -r '.source.label_selector // empty' <<< "$PAYLOAD")
  FIELD_SELECTOR=$(jq -r '.source.field_selector // empty' <<< "$PAYLOAD")
  if [ -n "$FIELD_SELECTOR" ]; then
      FLAGS+=("--field-selector=${FIELD_SELECTOR}")
  fi
  if [ -n "$LABEL_SELECTOR" ]; then
      FLAGS+=(-l "${LABEL_SELECTOR}")
  fi

  echo "${FLAGS[@]}"
}

outfile_extension() {
  local EXTENSION OUTPUT="$1"
  if [[ "$OUTPUT" =~ ^jsonpath= || "$OUTPUT" == ^jsonpath-file= || "$OUTPUT" == "json" ]]; then
    EXTENSION="json"
  elif [[ -z "$OUTPUT" || "$OUTPUT" == "wide" || "$OUTPUT" =~ ^custom-columns= || "$OUTPUT" == "name" ]]; then
    EXTENSION="txt"
  elif [[ "$OUTPUT" == "yaml" ]]; then
    EXTENSION="yaml"
  else
    EXTENSION="txt"
  fi
  echo $EXTENSION
}

# object_versions parses query JSON for a set of objects and returns the resourceVersion
# of each as a string. When multiple objects are queried the version string will
# be an ordered list of all of the resourceVersions
object_versions() {
  local OBJECT_JSON="$1" TRACING_ENABLED="$2"

  if [ "$TRACING_ENABLED" = "true" ]; then
    set -x
  fi

  ITEMS_LENGTH=$(jq -r '.items | length' <<< "$OBJECT_JSON")
  local VERSION_TRANSFORM
  if [ "$ITEMS_LENGTH" -eq 0 ]; then
    # Handle a single object result
    VERSION_TRANSFORM='.metadata.resourceVersion'
  else
    VERSION_TRANSFORM='.items | map(.metadata.resourceVersion) | join(" ")'
  fi
  echo "{\"resourceVersions\": \"$(jq -r "$VERSION_TRANSFORM" <<< "$OBJECT_JSON" | tr "")\"}"
}

# object_version_data parses query JSON for objects, and returns the latest
# resourceVersion as described in.bash object_versions along with common metadata for
# each object
object_version_data() {
  local OBJECT_JSON="$1" TRACING_ENABLED="$2"

  if [ "$TRACING_ENABLED" = "true" ]; then
    set -x
  fi

  OBJECT_VERSIONS=$(object_versions "$OBJECT_JSON" "$TRACING_ENABLED")

  ITEMS_LENGTH=$(jq -r '.items | length' <<< "$OBJECT_JSON")

  local METADATA_TRANSFORM METADATA
  if [ "$ITEMS_LENGTH" -eq 0 ]; then
    # Handle a single object result
    METADATA_TRANSFORM='[
      {name: (.kind + "/" + .metadata.name + " creationTimestamp"), value: .metadata.creationTimestamp},
      {name: (.kind + "/" + .metadata.name + " uid"), value: .metadata.uid},
      {name: (.kind + "/" + .metadata.name + " selfLink"), value: .metadata.selfLink}
    ]'
  else
    # Handle a plural object result
    METADATA_TRANSFORM='.items | map([
      {name: (.kind + "/" + .metadata.name + " creationTimestamp"), value: .metadata.creationTimestamp},
      {name: (.kind + "/" + .metadata.name + " uid"), value: .metadata.uid},
      {name: (.kind + "/" + .metadata.name + " selfLink"), value: .metadata.selfLink}
    ]) | flatten'
  fi
  METADATA=$( jq -r "$METADATA_TRANSFORM" <<< "$OBJECT_JSON")

  echo "{\"version\": ${OBJECT_VERSIONS}, \"metadata\": ${METADATA}}"
}

# setup_kubernetes create a Kubernetes configuration based on the source or parameters
setup_kubernetes() {
  local PAYLOAD=$1 SOURCE=$2 KUBECONFIG_RELATIVE

  KUBECONFIG_RELATIVE=$(jq -r '.params.kubeconfig_path // empty' <<< "$PAYLOAD")
  if [[ -n "$KUBECONFIG_RELATIVE" && -f "${SOURCE}/${KUBECONFIG_RELATIVE}" ]]; then
    export KUBECONFIG="${SOURCE}/${KUBECONFIG_RELATIVE}"
  else

    local CLUSTER_URL

    CLUSTER_URL=$(jq -r '.source.cluster_url // empty' <<< "$PAYLOAD")
    if [ -z "$CLUSTER_URL" ]; then
      >&2 echo "⚠️ Error: invalid payload: must provide either kubeconfig_path or cluster_url"
      kill -s TERM "$PID"
    fi

    if [[ "$CLUSTER_URL" =~ https.* ]]; then
      local INSECURE_CLUSTER CLUSTER_CA ADMIN_KEY ADMIN_CERT TOKEN TOKEN_PATH
      INSECURE_CLUSTER=$(jq -r '.source.insecure_cluster // "false"' <<< "$PAYLOAD")
      CLUSTER_CA=$(jq -r '.source.cluster_ca // empty' <<< "$PAYLOAD")
      ADMIN_KEY=$(jq -r '.source.admin_key // empty' <<< "$PAYLOAD")
      ADMIN_CERT=$(jq -r '.source.admin_cert // empty' <<< "$PAYLOAD")
      TOKEN=$(jq -r '.source.token // empty' <<< "$PAYLOAD")
      TOKEN_PATH=$(jq -r '.params.token_path // empty' <<< "$PAYLOAD")

      if [ "$INSECURE_CLUSTER" == "true" ]; then
        kubectl config set-cluster default --server="$CLUSTER_URL" --insecure-skip-tls-verify=true
      else
        local CA_PATH="/root/.kube/ca.pem"
        echo "$CLUSTER_CA" | base64 -d > $CA_PATH
        kubectl config set-cluster default --server="$CLUSTER_URL" --certificate-authority=$CA_PATH
      fi

      if [ -f "$SOURCE/$TOKEN_PATH" ]; then
        local TOKEN_CONTENT
        TOKEN_CONTENT=$(cat "$SOURCE/$TOKEN_PATH")
        kubectl config set-credentials admin --token="$TOKEN_CONTENT"
      elif [ ! -z "$TOKEN" ]; then
        kubectl config set-credentials admin --token="$TOKEN"
      else
        mkdir -p /root/.kube
        local KEY_PATH="/root/.kube/key.pem" CERT_PATH="/root/.kube/cert.pem"
        echo "$ADMIN_KEY" | base64 -d > $KEY_PATH
        echo "$ADMIN_CERT" | base64 -d > $CERT_PATH
        kubectl config set-credentials admin --client-certificate="$CERT_PATH" --client-key="$KEY_PATH"
      fi

      kubectl config set-context default --cluster=default --user=admin
    else
      kubectl config set-cluster default --server="$CLUSTER_URL"
      kubectl config set-context default --cluster=default
    fi

    kubectl config use-context default
  fi

  kubectl version
}