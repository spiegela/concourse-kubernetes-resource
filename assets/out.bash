#!/bin/bash

set -e
set -o pipefail

exec 3>&1 # make stdout available as fd 3 for the result
exec 1>&2 # redirect all output to stderr for logging

source /opt/resource/common.sh

SOURCE=$1
PAYLOAD=$(cat <&0)
DATE=$(date -Iseconds)

TRACING_ENABLED=$(jq -r '.source.tracing_enabled // empty' <<< "$PAYLOAD")
if [ "$TRACING_ENABLED" = "true" ]; then
  set -x
fi

source /opt/resource/common.sh

COMPONENTS_DIR=$(setup_components_dir "$PAYLOAD")

COMPONENT=$(jq -r '.source.component // empty' <<< "$PAYLOAD")
if [ -z "$COMPONENT" ]; then
  echo "source.component field is required ⚠️"
  exit 1
fi

VERSION=$(jq -r '.params.version // empty' <<< "$PAYLOAD")
if [ -z "$VERSION" ]; then
  VERSION=$(jq -r '.source.version // empty' <<< "$PAYLOAD")
fi

if [ -z "$VERSION" ]; then
  echo "source.version or params.version field is required ⚠️"
  exit 1
fi

pushd "$COMPONENTS_DIR"

  PUBLISH=$(jq -r '.params.publish // empty' <<< "$PAYLOAD")
  MANIFEST_JSON=$(jq -r '.params.manifest_json // empty' <<< "$PAYLOAD")
  MANIFEST_FILE=$(jq -r '.params.manifest_file // empty' <<< "$PAYLOAD")
  README_MD=$(jq -r '.params.readme_md // empty' <<< "$PAYLOAD")
  README_FILE=$(jq -r '.params.readme_file // empty' <<< "$PAYLOAD")

  if [ "$PUBLISH" == "true" ]; then
    mkdir -p "components/${COMPONENT}/${VERSION}"
    if [ -n "$MANIFEST_JSON" ]; then
      echo "$MANIFEST_JSON" > "components/${COMPONENT}/${VERSION}/artifacts.json"
    elif [ -n "$MANIFEST_FILE" ]; then
      if [ -f "$SOURCE/$MANIFEST_FILE" ]; then
        cp "$SOURCE/$MANIFEST_FILE" "components/${COMPONENT}/${VERSION}/artifacts.json"
      else
        echo "params.manifest_file field is supplied, but file does not exist ⚠️"
        exit 1
      fi
    else
      echo "params.publish field is true, but no manifest content specified via JSON or file ⚠️"
      exit 1
    fi

    if [ -n "$README_MD" ]; then
      echo "$README_MD" > "components/${COMPONENT}/${VERSION}/readme.md"
    elif [ -n "$README_FILE" ]; then
      if [ -f "$SOURCE/$README_FILE" ]; then
        cp "$SOURCE/$README_FILE" "components/${COMPONENT}/${VERSION}/readme.md"
      else
        echo "params.readme_file field is supplied, but file does not exist ⚠️"
        exit 1
      fi
    fi
    PUBLISHED="true"
  fi

  PROMOTE_TAG=$(jq -r '.params.promote // empty' <<< "$PAYLOAD")
  if [ -n "$PROMOTE_TAG" ]; then
    "$COMPONENTS_DIR/product" promote "$COMPONENT" "$VERSION" "$PROMOTE_TAG"
    PROMOTED="true"
  fi

  git add "components/${COMPONENT}"

  if [ -n "$(git status -s 2>&1)" ]; then
    # There are active changes in the repo, so commit and push
    git config user.name svc_npobjectscaleci
    git config user.email svc_npobjectscaleci@example.com

    if [ -n "$BUILD_NAME" ]; then
      BUILD_LINK="$ATC_EXTERNAL_URL/teams/$BUILD_TEAM_NAME/pipelines/$BUILD_PIPELINE_NAME/jobs/$BUILD_JOB_NAME/builds/$BUILD_NAME"
      PUB_FOOTER="* _[$DATE]_ [Published by $BUILD_PIPELINE_NAME]($BUILD_LINK)"
      PROM_FOOTER="* _[$DATE]_ [Promoted to $PROMOTE_TAG by $BUILD_PIPELINE_NAME]($BUILD_LINK)"
    else
      BUILD_LINK="Team: $BUILD_TEAM_NAME ID: $BUILD_ID"
      PUB_FOOTER="* _[$DATE]_ Published by $BUILD_LINK"
      PROM_FOOTER="* _[$DATE]_ [Promoted to $PROMOTE_TAG by $BUILD_LINK"
    fi

    FOOTER=$'\n'
    if [[ "$PUBLISHED" && "$PROMOTED" ]]; then
        MESSAGE="$COMPONENT:$VERSION published & promoted to $PROMOTE_TAG"
        FOOTER+="$PUB_FOOTER"
        FOOTER+=$'\n'
        FOOTER+="$PROM_FOOTER"
    elif [ -n "$PUBLISHED" ]; then
        MESSAGE="$COMPONENT:$VERSION published"
        echo "$FOOTER" >> "components/${COMPONENT}/${VERSION}/readme.md"
        FOOTER+="$PUB_FOOTER"
    elif [ -n "$PROMOTED" ]; then
        MESSAGE="$COMPONENT:$VERSION promoted to $PROMOTE_TAG"
        FOOTER+="$PROM_FOOTER"
    fi

    echo "$FOOTER" >> "components/${COMPONENT}/${VERSION}/readme.md"

    git add "components/${COMPONENT}"

    MESSAGE+=$'\n'
    MESSAGE+="Build: $BUILD_LINK"

    git commit -m "$MESSAGE"

    URI=$(jq -r '.source.uri // empty' <<< "$PAYLOAD")
    if [ -z "$URI" ]; then
        >&2 echo "source.uri field is required ⚠️"
        exit 1
    fi

    BRANCH=$(jq -r '.source.branch // "master"' <<< "$PAYLOAD")

    git push "$URI" "$BRANCH"
  fi

popd

>&3 component_version_data "$PAYLOAD" "$COMPONENT" "$VERSION"