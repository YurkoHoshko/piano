# Build a llama-swap image using the same CUDA base we build llama-server with.
ARG CUDA_BASE=llama-swap-cuda:base
ARG LLAMA_SWAP_VERSION=v174
FROM ${CUDA_BASE}
ARG LLAMA_SWAP_VERSION
ARG LLAMA_SWAP_ARCH

RUN set -eux; \
    version="${LLAMA_SWAP_VERSION#v}"; \
    arch="${LLAMA_SWAP_ARCH:-$(uname -m)}"; \
    case "$arch" in \
      x86_64|amd64) target_arch=amd64 ;; \
      aarch64|arm64) target_arch=arm64 ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/mostlygeek/llama-swap/releases/download/${LLAMA_SWAP_VERSION}/llama-swap_${version}_linux_${target_arch}.tar.gz"; \
    curl -fL "$url" -o /tmp/llama-swap.tar.gz; \
    tar -xzf /tmp/llama-swap.tar.gz -C /usr/local/bin llama-swap; \
    rm /tmp/llama-swap.tar.gz; \
    chmod +x /usr/local/bin/llama-swap


RUN apt-get update && apt-get install -y --no-install-recommends \

# Install mise and uv for Python package management
RUN curl https://mise.run | sh && \
    cp /root/.local/bin/mise /usr/local/bin/mise

ENV MISE_DATA_DIR="/root/.local/share/mise"
ENV MISE_CACHE_DIR="/root/.cache/mise"
ENV PATH="/root/.local/share/mise/shims:$PATH"

# Install Python 3.10 and uv
RUN mise use python@3.10 && \
    mise use uv

COPY out/llama-server /usr/local/bin/llama-server
RUN chmod +x /usr/local/bin/llama-server
COPY out/libllama.so /usr/local/lib/libllama.so
COPY out/libggml.so /usr/local/lib/libggml.so
COPY out/libmtmd.so /usr/local/lib/libmtmd.so
RUN ldconfig

ENTRYPOINT ["llama-swap"]
CMD ["--config", "/app/config.yaml", "--listen", "0.0.0.0:8080"]
