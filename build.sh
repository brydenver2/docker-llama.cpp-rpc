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

echo "[build] CPU  -> ${cpu_img}"
docker build --no-cache --pull -t "${cpu_img}" -f llama.cpp/Dockerfile .

echo "[build] CUDA -> ${cuda_img}"
docker build --no-cache --pull -t "${cuda_img}" -f llama.cpp/Dockerfile.cuda .

echo "[push] CPU  -> ${cpu_img}"
docker push "${cpu_img}"

echo "[push] CUDA -> ${cuda_img}"
docker push "${cuda_img}"

echo "Done."
