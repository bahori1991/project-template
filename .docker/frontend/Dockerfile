# syntax=docker/dockerfile:1

# --- Base Image from ../base ---
ARG DEV_BASE_IMAGE
FROM ${DEV_BASE_IMAGE}

# --- Set non-root user before install Vite+
ARG USERNAME
USER ${USERNAME}

# --- Install Vite+ --- 
ENV HOME=/home/${USERNAME}
ENV VP_NODE_MANAGER=yes
ENV VP_HOME="${HOME}/.local/share/vite-plus"
RUN curl -fsSL --proto "=https" --tlsv1.2 https://vite.plus -o /tmp/vite-plus-install.sh && \
    bash /tmp/vite-plus-install.sh && \
    rm -f /tmp/vite-plus-install.sh
ENV PATH="${VP_HOME}/bin:${PATH}"

# --- Set Entrypoint ---
COPY --chmod=755 entrypoint.sh /usr/local/bin/container-entrypoint.sh

# --- Set frontend ---
WORKDIR /app
EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/container-entrypoint.sh"]
CMD ["/usr/bin/sleep", "infinity"]
