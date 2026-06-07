#!/bin/bash

cd "$(dirname "$0")"

wait_for_backends() {
    local backends="$1"
    [ "$APP_MODE" = "server" ] || return 0
    [ -z "$backends" ] && return 0
    echo "\n[startup] waiting for RPC backends: $backends"
    for target in ${backends//,/ }; do
        local host="${target%%:*}"
        local port="${target##*:}"
        if [ -z "$host" ] || [ -z "$port" ]; then
            echo "[startup] skipping malformed backend entry: $target"
            continue
        fi
        echo "[startup] waiting for $host:$port"
        until nc -z "$host" "$port"; do
            sleep 5
        done
        echo "[startup] $host:$port is reachable"
    done
    echo "[startup] all RPC backends reachable"
}

# If arguments passed to the script — treat them as custom command
if [ "$#" -gt 0 ]; then
    echo && echo "Custom CMD detected, executing: $*" && echo
    exec "$@"
fi

# Default env setup
[ "x$APP_MODE" = "x" ] && export APP_MODE="backend"
[ "x$APP_BIND" = "x" ] && export APP_BIND="0.0.0.0"
[ "x$APP_MEM" = "x" ] && export APP_MEM="1024"
[ "x$APP_MODEL" = "x" ] && export APP_MODEL="/app/models/TinyLlama-1.1B-q4_0.gguf"
[ "x$APP_ROUTER_MODE" = "x" ] && export APP_ROUTER_MODE="false"
[ "x$APP_MODELS_DIR" = "x" ] && export APP_MODELS_DIR="/app/models"
[ "x$APP_MODELS_MAX" = "x" ] && unset APP_MODELS_MAX
[ "x$APP_MODELS_AUTOLOAD" = "x" ] && export APP_MODELS_AUTOLOAD="true"
[ "x$APP_REPEAT_PENALTY" = "x" ] && export APP_REPEAT_PENALTY="1.0"
[ "x$APP_GPU_LAYERS" = "x" ] && export APP_GPU_LAYERS="99"
[ "x$APP_THREADS" = "x" ] && export APP_THREADS="16"
[ "x$APP_DEVICE" = "x" ] && unset APP_DEVICE
[ "x$APP_CACHE" = "x" ] && export APP_CACHE="false"
[ "x$APP_EMBEDDING" = "x" ] && export APP_EMBEDDING="false"
[ "x$APP_POOLING" = "x" ] && unset APP_POOLING
[ "x$APP_CTX_SIZE" = "x" ] && unset APP_CTX_SIZE
[ "x$APP_NO_WARMUP" = "x" ] && export APP_NO_WARMUP="false"
[ "x$APP_PARALLEL" = "x" ] && export APP_PARALLEL="1"
[ "x$APP_FLASH_ATTN" = "x" ] && export APP_FLASH_ATTN="false"
[ "x$APP_CACHE_TYPE_K" = "x" ] && unset APP_CACHE_TYPE_K
[ "x$APP_CACHE_TYPE_V" = "x" ] && unset APP_CACHE_TYPE_V
[ "x$APP_SPEC_TYPE" = "x" ] && unset APP_SPEC_TYPE
[ "x$APP_SPEC_DRAFT_N_MAX" = "x" ] && unset APP_SPEC_DRAFT_N_MAX
[ "x$APP_SPEC_DRAFT_P_MIN" = "x" ] && unset APP_SPEC_DRAFT_P_MIN
[ "x$APP_NO_MMPROJ" = "x" ] && export APP_NO_MMPROJ="false"
[ "x$APP_KV_UNIFIED" = "x" ] && export APP_KV_UNIFIED="false"
[ "x$APP_CACHE_RAM" = "x" ] && unset APP_CACHE_RAM
[ "x$APP_TIMEOUT" = "x" ] && unset APP_TIMEOUT
[ "x$APP_BATCH_SIZE" = "x" ] && unset APP_BATCH_SIZE
[ "x$APP_UBATCH_SIZE" = "x" ] && unset APP_UBATCH_SIZE

# Construct the command with the options
if [ "$APP_MODE" = "backend" ]; then
    [ "x$APP_PORT" = "x" ] && export APP_PORT="50052"
    # RPC backend
    CMD="/app/rpc-server"
    CMD+=" --host $APP_BIND"
    CMD+=" --port $APP_PORT"
    CMD+=" --threads $APP_THREADS"
    [ -n "$APP_DEVICE" ] && CMD+=" --device $APP_DEVICE"
    [ "$APP_CACHE" = "true" ] && CMD+=" --cache"
elif [ "$APP_MODE" = "server" ]; then
    [ "x$APP_PORT" = "x" ] && export APP_PORT="8080"
    # API server connected to multipla backends
    CMD="/app/llama-server"
    CMD+=" --host $APP_BIND"
    CMD+=" --port $APP_PORT"
    if [ "$APP_ROUTER_MODE" = "true" ]; then
        [ -n "$APP_MODELS_DIR" ] && CMD+=" --models-dir $APP_MODELS_DIR"
        [ -n "$APP_MODELS_MAX" ] && CMD+=" --models-max $APP_MODELS_MAX"
        [ "$APP_MODELS_AUTOLOAD" = "false" ] && CMD+=" --no-models-autoload"
    else
        CMD+=" --model $APP_MODEL"
    fi
    CMD+=" --repeat-penalty $APP_REPEAT_PENALTY"
    CMD+=" --gpu-layers $APP_GPU_LAYERS"
    if [ -n "$APP_RPC_BACKENDS" ]; then
        wait_for_backends "$APP_RPC_BACKENDS"
        CMD+=" --rpc $APP_RPC_BACKENDS"
    fi
    [ -n "$APP_CTX_SIZE" ] && CMD+=" --ctx-size $APP_CTX_SIZE"
    [ -n "$APP_BATCH_SIZE" ] && CMD+=" --batch-size $APP_BATCH_SIZE"
    [ -n "$APP_UBATCH_SIZE" ] && CMD+=" --ubatch-size $APP_UBATCH_SIZE"
    [ "$APP_NO_WARMUP" = "true" ] && CMD+=" --no-warmup"
    [ "$APP_EMBEDDING" = "true" ] && CMD+=" --embedding"
    [ -n "$APP_POOLING" ] && CMD+=" --pooling $APP_POOLING"
    CMD+=" --parallel $APP_PARALLEL"
    case "$APP_FLASH_ATTN" in
        true|on)   CMD+=" --flash-attn on" ;;
        off|false) CMD+=" --flash-attn off" ;;
        auto)      CMD+=" --flash-attn auto" ;;
    esac
    [ -n "$APP_CACHE_TYPE_K" ] && CMD+=" --cache-type-k $APP_CACHE_TYPE_K"
    [ -n "$APP_CACHE_TYPE_V" ] && CMD+=" --cache-type-v $APP_CACHE_TYPE_V"
    [ -n "$APP_SPEC_TYPE" ] && CMD+=" --spec-type $APP_SPEC_TYPE"
    [ -n "$APP_SPEC_DRAFT_N_MAX" ] && CMD+=" --spec-draft-n-max $APP_SPEC_DRAFT_N_MAX"
    [ -n "$APP_SPEC_DRAFT_P_MIN" ] && CMD+=" --spec-draft-p-min $APP_SPEC_DRAFT_P_MIN"
    [ "$APP_NO_MMPROJ" = "true" ] && CMD+=" --no-mmproj"
    [ "$APP_KV_UNIFIED" = "true" ] && CMD+=" --kv-unified"
    if [ -n "$APP_CACHE_RAM" ] && [ "$APP_CACHE_RAM" -gt 0 ] 2>/dev/null; then
        CMD+=" --cache-ram $APP_CACHE_RAM"
    fi
    [ -n "$APP_TIMEOUT" ] && CMD+=" --timeout $APP_TIMEOUT"
elif [ "$APP_MODE" = "none" ]; then
    # For cases when you want to use /app/llama-cli
    echo "APP_MODE is set to none. Sleeping indefinitely."
    CMD="sleep inf"
else
    echo "Invalid APP_MODE specified: $APP_MODE"
    exit 1
fi

# Execute the command
echo && echo "Executing command: $CMD" && echo
exec $CMD
exit 0
