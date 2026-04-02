#!/usr/bin/env bash
set -euo pipefail

# Build and push CPU and CUDA images to local registry
# Usage: ./build.sh [tag]
# Default tag: contents of version.txt (if present), else 'latest'

if [ -f version.txt ] && [ -z "${1:-}" ]; then
  TAG=$(tr -d '\n' < version.txt)
else
  TAG=${1:-latest}
fi

REGISTRY=registry.local.wallacearizona.us
IMAGE_BASE="$REGISTRY/llama.cpp-rpc"

cpu_img="${IMAGE_BASE}:${TAG}"
cuda_img="${IMAGE_BASE}:${TAG}-cuda"

# Retry function for push operations (handles timeouts/connection resets)
push_with_retry() {
  local image=$1
  local max_retries=3
  local retry=0
  
  while [ $retry -lt $max_retries ]; do
    echo "[push] Attempt $((retry + 1))/${max_retries}: ${image}"
    if docker push "${image}"; then
      echo "[push] Success: ${image}"
      return 0
    fi
    retry=$((retry + 1))
    if [ $retry -lt $max_retries ]; then
      echo "[push] Failed, retrying in 5 seconds..."
      sleep 5
    fi
  done
  
  echo "[push] ERROR: Failed after ${max_retries} attempts: ${image}"
  return 1
}

# Build with BuildKit and caching enabled (remove --no-cache for faster rebuilds)
export DOCKER_BUILDKIT=1

echo "[build] CPU  -> ${cpu_img}"
docker build --pull -t "${cpu_img}" -f llama.cpp/Dockerfile .

echo "[build] CUDA -> ${cuda_img}"
docker build --pull -t "${cuda_img}" -f llama.cpp/Dockerfile.cuda .

echo "[push] CPU  -> ${cpu_img}"
push_with_retry "${cpu_img}"

echo "[push] CUDA -> ${cuda_img}"
push_with_retry "${cuda_img}"

echo "Done."
