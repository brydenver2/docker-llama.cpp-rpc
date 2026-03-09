# llama.cpp RPC-server in Docker

[Русский](./README.md) | [中文](./README.zh.md) | **English**

This is a fork of [EvilFreelancer/docker-llama.cpp-rpc](https://github.com/EvilFreelancer/docker-llama.cpp-rpc) with modifications to build against **OpenBLAS** instead of Intel MKL, resolving `libmtmd.so.0` runtime dependency issues.

This project is based on [llama.cpp](https://github.com/ggerganov/llama.cpp) and compiles only
the [RPC](https://github.com/ggerganov/llama.cpp/tree/master/examples/rpc) server, along with auxiliary utilities
operating in RPC client mode, which are necessary for implementing distributed inference of Large Language Models (LLMs)
and Embedding Models converted into the GGUF format.

## Changes from Upstream

- **OpenBLAS Runtime**: Switched from Intel MKL to OpenBLAS (`libopenblas0`) to avoid missing library errors
- **Build Script**: Added `build.sh` for automated builds with versioning from `version.txt`
- **Local Registry**: Configured for deployment to `registry.local.wallacearizona.us`
- **BLAS Support**: Enabled `-DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS` for improved CPU performance
- **Server Startup Guard**: `entrypoint.sh` now waits for every address in `APP_RPC_BACKENDS` to respond before launching `llama-server`

## Overview

The general architecture of an application using the RPC server looks as follows:

![schema](./assets/schema.png)

Instead of `llama-server`, you can use `llama-cli` or `llama-embedding`, which are included in the standard container
package.

Docker images are built with support for the following architectures:

* **CPU-only** - amd64, arm64, arm/v7
* **CUDA** - amd64

Unfortunately, CUDA builds for arm64 fail due to an error, so they are temporarily disabled.

## Environment Variables

| Name               | Default                                    | Description                                                                                      |
|--------------------|--------------------------------------------|--------------------------------------------------------------------------------------------------|
| APP_MODE           | backend                                    | Container operation mode, available options: server, backend, and none                           |
| APP_BIND           | 0.0.0.0                                    | Interface to bind to                                                                             |
| APP_PORT           | `8080` for `server`, `50052` for `backend` | Port number on which the server is running                                                       |
| APP_MEM            | 1024                                       | Amount of MiB of RAM available to the client; in CUDA mode, this is the amount of GPU memory     | 
| APP_RPC_BACKENDS   | backend-cuda:50052,backend-cpu:50052       | Comma-separated addresses of backends that the container will try to connect to in `server` mode |
| APP_MODEL          | /app/models/TinyLlama-1.1B-q4_0.gguf       | Path to the model weights inside the container                                                   | 
| APP_REPEAT_PENALTY | 1.0                                        | Repeat penalty                                                                                   |
| APP_GPU_LAYERS     | 99                                         | Number of layers offloaded to the backend                                                        |
| APP_ROUTER_MODE    | false                                      | Enable llama.cpp router mode (omit `--model` and route by request `model` field)                  |
| APP_MODELS_DIR     | /app/models                                | Directory scanned for GGUF files when router mode is enabled                                     |
| APP_MODELS_MAX     | unset                                      | Maximum simultaneously loaded models before router performs LRU eviction                         |
| APP_MODELS_AUTOLOAD | true                                      | Autoload models on first request; set to `false` to require explicit `/models/load` calls       |

### Docker Swarm Guidance

When you deploy this image with `docker stack deploy`, keep these points in mind so DNS resolution works even when services join multiple overlay networks:

- **Stack-qualified service names**: Swarm registers services as `<stack>_<service>` on each shared overlay. Set `APP_RPC_BACKENDS` to those names (e.g. `APP_RPC_BACKENDS=llamaccp_backend-cuda-1:50052`) unless you create explicit network aliases.
- **Shared overlay network**: Ensure the server and all backends attach to at least one common overlay network (e.g. `llama_rpc`). If a service participates in multiple networks, Swarm advertises the FQDN on each, so the server must connect over the network that actually reaches the backends.
- **Optional aliases**: If you prefer short hostnames, define per-service aliases within the shared network:

  ```yaml
  backend-cuda-1:
    networks:
      llama_rpc:
        aliases:
          - backend-cuda-1
  ```

  The server may then reference `backend-cuda-1:50052`, and Swarm keeps that alias inside the overlay regardless of the stack prefix.
- **Startup ordering**: `entrypoint.sh` automatically waits for every backend target to accept TCP connections before the server process starts, preventing initial connection errors during stack rollouts or node reschedules.

### Router Mode Quick Start

Router mode (introduced in [the Hugging Face llama.cpp model-management post](https://huggingface.co/blog/ggml-org/model-management-in-llamacpp)) lets one `llama-server` hot-load multiple GGUF models on demand. Enable it by setting `APP_ROUTER_MODE=true` and, optionally, tweaking `APP_MODELS_DIR`, `APP_MODELS_MAX`, or disabling autoload. After the container starts you can:

- `GET /models` to inspect discovered GGUFs and their `loaded` status.
- `POST /v1/chat/completions` with the desired `model` name to load and serve that model on demand.
- `POST /models/load` or `/models/unload` to pre-stage or evict specific models.

Persist the llama.cpp cache (`~/.cache/llama.cpp` inside the container) if you rely on auto-downloaded weights so repeated runs do not redownload.

## Example of docker-compose.yml

In this example, `llama-server` (container `main`) is launched and the
model [TinyLlama-1.1B-q4_0.gguf](https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/tree/main), which was
previously downloaded to the `./models` directory located at the same level as `docker-compose.yml`, is initialized. The
`./models` directory is then mounted inside the `main` container and is available at the path `/app/models`.

```yaml
version: "3.9"

x-build-cpu: &build-cpu
  context: .
  dockerfile: llama.cpp/Dockerfile
  args:
    LLAMACPP_VERSION: master

x-build-cuda: &build-cuda
  context: .
  dockerfile: llama.cpp/Dockerfile.cuda
  args:
    LLAMACPP_VERSION: master

services:

  main:
    build: *build-cpu
    restart: unless-stopped
    volumes:
      - ./models:/app/router-models
      - ./router-cache:/root/.cache/llama.cpp
    environment:
      APP_MODE: server
      APP_ROUTER_MODE: "true"
      APP_MODELS_DIR: /app/router-models
      APP_MODELS_MAX: 4
      APP_MODELS_AUTOLOAD: "true"
      APP_RPC_BACKENDS: backend-cuda:50052,backend-cpu:50052
    ports:
      - "127.0.0.1:8080:8080"

  backend-cpu:
    build: *build-cpu
    restart: unless-stopped
    environment:
      APP_MODE: backend
      APP_MEM: 2048
    ports:
      - "127.0.0.1:50152:50052"

  backend-cuda:
    build: *build-cuda
    restart: unless-stopped
    environment:
      APP_MODE: backend
      APP_MEM: 1024
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [ gpu ]
```

The bundled Dockerfiles already default to `LLAMACPP_VERSION=master`, so every `docker compose build` pulls the freshest upstream code that includes router mode.

A complete example is available in [docker-compose.dist.yml](./docker-compose.dist.yml).

As a result, we obtain the following diagram:

![schema-example](./assets/schema-example.png)

Once launched, you can make HTTP requests like this:

```shell
curl \
    --request POST \
    --url http://localhost:8080/completion \
    --header "Content-Type: application/json" \
    --data '{"prompt": "Building a website can be done in 10 simple steps:"}'
```

## Building and Deploying

### Automated Build Script

Use the included `build.sh` script to build and push both CPU and CUDA images to your local registry:

```shell
# Build and push using version from version.txt (default: v0.0.1)
./build.sh

# Build and push with custom version tag
./build.sh v1.0.0
```

The script will:
- Build CPU image: `registry.local.wallacearizona.us/llama.cpp-rpc:<tag>`
- Build CUDA image: `registry.local.wallacearizona.us/llama.cpp-rpc:<tag>-cuda`
- Push both images to the registry
- Use `--no-cache --pull` to ensure fresh builds

### Manual Docker Build

Building containers in CPU-only mode:

```shell
docker build --no-cache --pull -t llama-cpu -f llama.cpp/Dockerfile .
```

Building the container for CUDA:

```shell
docker build --no-cache --pull -t llama-cuda -f llama.cpp/Dockerfile.cuda .
```

Using the build argument `LLAMACPP_VERSION`, you can specify the tag version, branch name, or commit hash to build the
container from. By default, the `master` branch is specified in the container.

```shell
# Build the container from a specific llama.cpp tag
docker build -f llama.cpp/Dockerfile --build-arg LLAMACPP_VERSION=b3700 .

# Build from master branch (default)
docker build -f llama.cpp/Dockerfile .
```

## Manual Build Using Docker Compose

An example of docker-compose.yml that performs image building with an explicit tag specification:

```yaml
version: "3.9"

services:

  main:
    restart: "unless-stopped"
    build:
      context: ./llama.cpp
      args:
        - LLAMACPP_VERSION=b3700
    volumes:
      - ./models:/app/models
    environment:
      APP_MODE: none
    ports:
      - "8080:8080"

  backend:
    restart: "unless-stopped"
    build:
      context: ./llama.cpp
      args:
        - LLAMACPP_VERSION=b3700
    environment:
      APP_MODE: backend
    ports:
      - "50052:50052"
```

## Version Management

The current version is tracked in `version.txt`. Update this file when releasing new versions:

```shell
echo "v0.0.2" > version.txt
./build.sh  # Automatically uses version from file
```

## Links

- Original project: https://github.com/EvilFreelancer/docker-llama.cpp-rpc
- llama.cpp RPC: https://github.com/ggerganov/llama.cpp/tree/master/examples/rpc
- llama.cpp repo: https://github.com/ggerganov/llama.cpp
- Related discussions:
  - https://github.com/ggerganov/ggml/pull/761
  - https://github.com/ggerganov/llama.cpp/issues/7293
  - https://github.com/ggerganov/llama.cpp/pull/6829
  - https://github.com/mudler/LocalAI/pull/2324
  - https://github.com/ollama/ollama/issues/4643

## Credits

Original project by [Pavel Rykov](https://github.com/EvilFreelancer) (2024).

This fork maintained by brydenver2 with modifications for OpenBLAS support and local registry deployment.
