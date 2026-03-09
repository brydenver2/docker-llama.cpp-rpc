FROM ubuntu:24.04 AS builder
WORKDIR /app
COPY llama.cpp/patches /tmp/patches

ARG LLAMACPP_REPO="https://github.com/ggerganov/llama.cpp.git"
# It may be name of branch, tag or commit hash
ARG LLAMACPP_VERSION="master"

# To get latest tag use this:
# git -c 'versionsort.suffix=-' ls-remote --tags --sort='v:refname' \
#    "https://github.com/ggerganov/llama.cpp.git" 'b*' | \
#    tail --lines=1 | cut --delimiter='/' --fields=3
# For details see here: https://stackoverflow.com/questions/8932389/git-shallow-clone-to-specific-tag)

# Install dependencies (no MKL/BLAS in builder)
RUN set -xe \
 && apt update -q \
 && apt install -fyq bash wget git cmake make g++ curl libcurl4-openssl-dev pkg-config libopenblas-dev \
 && apt remove -y 'intel-oneapi-*' 'intel-*' 'mkl*' 2>/dev/null || true \
 && find /usr -name "*mkl*" -delete 2>/dev/null || true \
 && apt clean

# Clone repo and apply local patches
RUN set -xe \
 && git clone --branch "$LLAMACPP_VERSION" --depth 1 "$LLAMACPP_REPO" \
 && cd llama.cpp \
 && if [ -d /tmp/patches ]; then \
		for patch in /tmp/patches/*.patch; do \
			[ -f "${patch}" ] || continue; \
			echo "Applying ${patch##*/}"; \
			git apply "${patch}"; \
		done; \
	fi

# Build binaries
WORKDIR /app/llama.cpp
RUN set -xe \
 && echo "Checking for MKL before build..." \
 && ! dpkg -l | grep -i mkl || (echo "MKL found, aborting" && exit 1) \
 && ! find /usr -name "*mkl*" | grep -q . || (echo "MKL files found, aborting" && find /usr -name "*mkl*" && exit 1) \
 && echo "Building without MKL/BLAS at $(date)" \
 && cmake -B build -DGGML_RPC=ON -DGGML_BLAS=OFF -DGGML_MKL=OFF -DBLA_VENDOR=OpenBLAS -DLLAMA_BUILD_TESTS=OFF -DGGML_BUILD_TESTS=OFF -DCMAKE_DISABLE_FIND_PACKAGE_BLAS=TRUE -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON -DMKL_ROOT= -DMKL_INCLUDE_DIR= -DMKL_LIBRARY= \
 && cmake --build build --config Release -j$(nproc) \
 && echo "Build completed at $(date)" \
 && ls -la build/bin/llama-server


FROM ubuntu:24.04
WORKDIR /app

# Install basic dependencies and OpenBLAS runtime
RUN set -xe \
 && apt update -q \
 && apt install -fyq libgomp1 curl libopenblas0 netcat-openbsd wget \
 && apt clean

# Create folders
RUN set -xe \
 && mkdir -pv /app/models

# Copy compiled tools
COPY --from=builder /app/llama.cpp/build/bin/*.so /usr/lib/x86_64-linux-gnu
COPY --from=builder /app/llama.cpp/build/bin/libmtmd.so.0 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /app/llama.cpp/build/bin/rpc-server .
COPY --from=builder /app/llama.cpp/build/bin/llama-cli .
COPY --from=builder /app/llama.cpp/build/bin/llama-embedding .
COPY --from=builder /app/llama.cpp/build/bin/llama-server .

# Remove any MKL libraries and binaries that might have been copied
RUN set -xe \
 && rm -f /app/llama-*mtmd* /app/test-mtmd* \
 && echo "Creating symlinks for llama libraries" \
 && ln -sf /usr/lib/x86_64-linux-gnu/libllama.so /usr/lib/x86_64-linux-gnu/libllama.so.0 \
 && ln -sf /usr/lib/x86_64-linux-gnu/libggml.so /usr/lib/x86_64-linux-gnu/libggml.so.0 \
 && ln -sf /usr/lib/x86_64-linux-gnu/libggml-base.so /usr/lib/x86_64-linux-gnu/libggml-base.so.0 \
 && ln -sf /usr/lib/x86_64-linux-gnu/libggml-cpu.so /usr/lib/x86_64-linux-gnu/libggml-cpu.so.0 \
 && ln -sf /usr/lib/x86_64-linux-gnu/libggml-rpc.so /usr/lib/x86_64-linux-gnu/libggml-rpc.so.0 \
 && ldconfig

# Init entrypoint
ADD llama.cpp/entrypoint.sh .
ENTRYPOINT ["/app/entrypoint.sh"]
