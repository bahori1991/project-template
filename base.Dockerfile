# syntax=docker/dockerfile:1

# Build tree-sitter-cli by cargo
FROM rust:1-bookworm AS tree-sitter-cli
ARG TREE_SITTER_CLI_VERSION
RUN apt update && \
    apt install -y --no-install-recommends clang pkg-config build-essential && \
    rm -rf /var/lib/apt/lists/* && \
    cargo install tree-sitter-cli --locked --version "${TREE_SITTER_CLI_VERSION}"

# Install Ubuntu (base image)
FROM ubuntu:24.04
 
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

ARG UID
ARG GID
ARG USERNAME
ARG EZA_VERSION
ARG NVIM_VERSION

# Install essential-packages
RUN apt update &&\
    apt install -y --no-install-recommends \
      ca-certificates curl git tzdata ripgrep fd-find build-essential unzip tar procps jq && \
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

# --- Delete a default user and default group 'ubuntu'
RUN userdel -r ubuntu 2>/dev/null || true; groupdel ubuntu 2>/dev/null || true

# --- Create a non-root user ---
RUN groupadd -g "${GID}" "${USERNAME}" && \
    useradd -m -u "${UID}" -g "${GID}" -s /bin/bash "${USERNAME}"

# --- Create a .config and .local/share directories ---
RUN install -d -m 0755 -o "${USERNAME}" -g "${GID}" \
    "/home/${USERNAME}/.config" \
    "/home/${USERNAME}/.local" \
    "/home/${USERNAME}/.local/bin" \
    "/home/${USERNAME}/.local/share" \
    "/home/${USERNAME}/.local/state"

USER ${USERNAME}

# --- Install Claude Code (native installer, places binary in ~/.local/bin) ---
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
RUN curl -fsSL --proto "=https" --tlsv1.2 https://claude.ai/install.sh -o /tmp/claude-install.sh && \
    bash /tmp/claude-install.sh && \
    rm -f /tmp/claude-install.sh && \
    claude --version

# --- Install graphify (uv manages its own Python) ---
RUN curl -fsSL https://astral.sh/uv/install.sh | sh && \
    uv tool install graphifyy && \
    graphify --help > /dev/null

CMD ["/usr/bin/sleep", "infinity"]

