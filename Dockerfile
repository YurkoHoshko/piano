# Build stage
ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.2
ARG DEBIAN_VERSION=bookworm-20241202-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Prepare build dir
WORKDIR /piano/runtime

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

# Compile assets
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Build release
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# Start a new build stage for the final image
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y \
    libstdc++6 openssl libncurses5 locales ca-certificates curl git sudo \
    chromium chromium-driver \
    fonts-liberation fonts-noto-color-emoji fonts-dejavu fontconfig \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install mise for runtime version management
RUN curl https://mise.run | sh && \
    cp /root/.local/bin/mise /usr/local/bin/mise

# Install Codex CLI from GitHub release (musl build for glibc compatibility)
RUN curl -L https://github.com/openai/codex/releases/download/rust-v0.93.0/codex-x86_64-unknown-linux-musl.tar.gz | tar xz -C /usr/local/bin && \
    mv /usr/local/bin/codex-x86_64-unknown-linux-musl /usr/local/bin/codex

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /piano/runtime

# Create a non-privileged user to run the app with passwordless sudo
RUN useradd --create-home app && \
    echo "app ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
RUN mkdir -p /data /piano/runtime /piano/agents && chown -R app:app /data /piano

# Create mise directories with proper ownership for the app user
RUN mkdir -p /home/app/.cache/mise /home/app/.local/share/mise /home/app/.local/state/mise && \
    chown -R app:app /home/app/.cache /home/app/.local

# Set mise environment variables for the app user
ENV MISE_DATA_DIR="/home/app/.local/share/mise"
ENV MISE_CACHE_DIR="/home/app/.cache/mise"
ENV PATH="/home/app/.local/share/mise/shims:$PATH"

# Set runner ENV
ENV MIX_ENV="prod"
ENV DATABASE_PATH="/data/piano.db"
ENV CODEX_HOME="/piano/agents/.codex"

# Browser agent configuration
ENV BROWSER_AGENT_ENABLED="false"
ENV BROWSER_AGENT_DRIVER="chrome"
ENV CHROMEDRIVER_PATH="/usr/bin/chromedriver"
ENV CHROME_BIN="/usr/bin/chromium"

# Copy the release from builder
COPY --from=builder --chown=app:app /piano/runtime/_build/${MIX_ENV}/rel/piano ./
COPY --chown=app:app .codex /piano/agents/.codex
COPY --chown=app:app .agents/AGENTS.md /piano/agents/AGENTS.md

USER app

# If using an environment that doesn't automatically reap zombie processes,
# you may want to add tini or another entry point that can do that
CMD ["/piano/runtime/bin/server"]
