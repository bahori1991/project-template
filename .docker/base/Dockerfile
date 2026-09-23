# syntax=docker/dockerfile:1

# Install tree-sitter-cli by cargo
FROM rust:1-bookworm AS tree-sitter-cli
ARG TREE_SITTER_CLI_VERSION=0.26.11
RUN apt update && \
    apt install -y --no-install-recommends clang pkg-config build-essential && \
    rm -rf /var/lib/apt/lists/* && \
    cargo install tree-sitter-cli --locked --version "${TREE_SITTER_CLI_VERSION}"

# Install Ubuntu (docker-image)
FROM ubuntu:24.04
 
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo

ARG UID=1000
ARG GID=1000
ARG USERNAME=user
ARG EZA_VERSION=v0.23.5
ARG NVIM_VERSION=v0.12.5

# Install essential-packages
RUN apt update &&\
    apt install -y --no-install-recommends \
      ca-certificates curl git tzdata ripgrep fd-find build-essential unzip tar procps && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# --- Install eza from GitHub ---
RUN curl -fsSL \
  "https://github.com/eza-community/eza/releases/download/${EZA_VERSION}/eza_x86_64-unknown-linux-gnu.tar.gz" \
    -o /tmp/eza.tar.gz && \
    tar -xzf /tmp/eza.tar.gz -C /tmp && \
    install -m 755 /tmp/eza /usr/local/bin/eza && \
    rm -f /tmp/eza.tar.gz /tmp/eza

# --- Set tree-sitter-cli binary ---
COPY --from=tree-sitter-cli /usr/local/cargo/bin/tree-sitter /usr/local/bin/tree-sitter

# --- Install Neovim appimage ---
RUN curl -fsSL \
  "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.appimage" \
    -o /tmp/nvim.appimage && \
  chmod u+x /tmp/nvim.appimage && \
  /tmp/nvim.appimage --appimage-extract && \
  mv squashfs-root /opt/nvim && \
  ln -sf /opt/nvim/usr/bin/nvim /usr/local/bin/nvim && \
  rm -f /tmp/nvim.appimage

# --- Create a non-root user ---
RUN groupadd -g "${GID}" "${USERNAME}" && \
    useradd -m -u "${UID}" -g "${GID}" -s /bin/bash "${USERNAME}"


