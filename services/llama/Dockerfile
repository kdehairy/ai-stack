# --- Stage 1: Build -----------------------------------------------------------
FROM rocm/dev-ubuntu-24.04:7.2.4 AS builder

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    curl \
    libcurl4-openssl-dev \
		hipblas-dev \
		rocblas-dev \
		rocwmma-dev \
    && rm -rf /var/lib/apt/lists/*

ARG LLAMA_VERSION=master
ARG GPU_TARGETS
# No fallback to master: a mistyped tag must fail the build, not silently build something else.
RUN git clone --depth=1 --branch ${LLAMA_VERSION} \
    https://github.com/ggml-org/llama.cpp /build/llama.cpp

WORKDIR /build/llama.cpp

# LLAMA_USE_PREBUILT_UI=OFF: build llama-server without its embedded web UI (OpenWebUI is
# the chat front end; the API is unaffected). The prebuilt UI is downloaded from a Hugging
# Face bucket keyed by build number, which the --depth=1 clone reports as "b1"; that 404s
# and falls back to the newest "latest" UI, which an older tag's asset check can reject
# (v1.0.0: "missing required asset(s): workbox[hash].js").
RUN test -n "${GPU_TARGETS}" || { echo "GPU_TARGETS build arg is required"; exit 1; } \
    && cmake -B build \
    -DGGML_HIP=ON \
    -DGPU_TARGETS="${GPU_TARGETS}" \
		-DGGML_HIP_ROCWMMA_FATTN=ON \
    -DGGML_CUDA_FORCE_MMQ=ON \
    -DBUILD_SHARED_LIBS=OFF \
		-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_USE_PREBUILT_UI=OFF \
    && cmake --build build --config Release -j$(nproc) \
             --target llama-server llama-cli llama-bench

# --- Stage 2: Runtime ---------------------------------------------------------
FROM rocm/dev-ubuntu-24.04:7.2.4 AS runtime

ARG AI_UID=1100
ARG AI_GID=1100

RUN apt-get update && apt-get install -y \
    libcurl4 \
		hipblas \
		rocblas \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/llama.cpp/build/bin/llama-server /usr/local/bin/
COPY --from=builder /build/llama.cpp/build/bin/llama-cli    /usr/local/bin/
COPY --from=builder /build/llama.cpp/build/bin/llama-bench  /usr/local/bin/

RUN groupadd --gid ${AI_GID} ai \
    && useradd --uid ${AI_UID} --gid ${AI_GID} --no-create-home --shell /sbin/nologin ai \
    && usermod -aG video,render ai

VOLUME ["/data/models/llamacpp"]

EXPOSE 8080

USER ai

ENTRYPOINT ["llama-server"]
