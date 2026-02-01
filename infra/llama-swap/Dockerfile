# Custom llama-swap image with Python and vLLM support for Qwen3-ASR
FROM local/llama-swap:custom

# Install mise for Python version management
RUN curl https://mise.run | sh && \
    cp /root/.local/bin/mise /usr/local/bin/mise

# Set mise environment
ENV MISE_DATA_DIR="/root/.local/share/mise"
ENV MISE_CACHE_DIR="/root/.cache/mise"
ENV PATH="/root/.local/share/mise/shims:$PATH"

# Install Python 3.10 using mise
RUN mise use python@3.10

# Install uv using mise
RUN mise use uv

# Create virtual environment for vLLM
RUN uv venv /opt/vllm-venv

# Install vLLM and qwen-asr dependencies
RUN uv pip install --python /opt/vllm-venv/bin/python \
    vllm \
    torch \
    transformers \
    numpy \
    accelerate

# Make vLLM available in PATH
ENV PATH="/opt/vllm-venv/bin:$PATH"

# Set environment variables for HuggingFace cache
ENV HF_HOME=/models/.cache/huggingface
ENV TRANSFORMERS_CACHE=/models/.cache/huggingface

# Ensure the container can access GPU
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

WORKDIR /app

# The entrypoint and command from the base image will be preserved
# llama-swap will be started with the config mounted at runtime
