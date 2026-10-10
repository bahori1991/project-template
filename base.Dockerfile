# syntax=docker/dockerfile:1

# Install Ubuntu (base image)
FROM ubuntu:24.04
 
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo
ENV LANG=ja_JP.utf8
ENV LC_ALL=ja_JP.utf8
ENV LANGUAGE=ja_JP:ja

ARG UID
ARG GID
ARG USERNAME

# Install essential-packages
RUN apt update &&\
    apt install -y --no-install-recommends \
      ca-certificates curl git tzdata locales ripgrep fd-find build-essential unzip tar procps && \
    sed -i '/ja_JP.UTF-8/s/^# //' /etc/locale.gen && \
    locale-gen ja_JP.UTF-8 && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# --- Delete a default user and default group 'ubuntu'
RUN userdel -r ubuntu 2>/dev/null || true; groupdel ubuntu 2>/dev/null || true

# --- Create a non-root user ---
RUN groupadd -g "${GID}" "${USERNAME}" && \
    useradd -m -u "${UID}" -g "${GID}" -s /bin/bash "${USERNAME}"

# --- Create a .config and .local/share directories ---
RUN install -d -m 0755 -o "${USERNAME}" -g "${GID}" \
    "/home/${USERNAME}/.config" \
    "/home/${USERNAME}/.local/share"
