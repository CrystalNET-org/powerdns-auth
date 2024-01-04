#!/usr/bin/env bash
set -e

IMAGES=( "powerdns" )
if [[ ${CI_COMMIT_TAG}  ]]; then
  VERSION=$CI_COMMIT_TAG
else
  VERSION="0.0.1-devnotworking"
fi
REPO=${CI_REGISTRY_IMAGE}
#REPO=harbor.harbor-dev.internal.ing.staging.k8s.gfsrv.net/jitsi
PUSH=NO
BUILD_ARGS=()
CommitMessage=

# Parse command line params
while [[ $# -gt 0 ]]; do
  arg="$1";
  
  case $arg in
    --push)
      PUSH=YES
    ;;
    --pull)
      BUILD_ARGS+=("--pull")
    ;;
    --no-cache)
      BUILD_ARGS+=("--no-cache")
    ;;
    *)
      break
    ;;
  esac

  shift
done

for IMAGE in "${IMAGES[@]}"
do
  IMAGE_TAG_PATCH=${REPO}/${IMAGE}:${VERSION}
  IMAGE_TAG=${REPO}/${IMAGE}:${VERSION%-*}
  IMAGE_LATEST=${REPO}/${IMAGE}:latest
  docker build \
      -t "${IMAGE_TAG}" \
      -t "${IMAGE_TAG_PATCH}" \
      -t "${IMAGE_LATEST}" \
      -f ./Dockerfile \
      ./

  if [[ ${PUSH} = YES ]]; then
    if [[ ${CI_COMMIT_TAG} ]]; then
      docker push ${IMAGE_TAG_PATCH}
      docker push ${IMAGE_TAG}
      docker push ${IMAGE_LATEST}
     else
      docker push ${IMAGE_TAG}
    fi
  fi
done
