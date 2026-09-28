# syntax=docker/dockerfile:1

# --- Base Image from ../base ---
ARG DEV_BASE_IMAGE
FROM ${DEV_BASE_IMAGE}

ARG USERNAME

# --- Install .NET 10 ---
ENV HOME=/home/${USERNAME}
ENV DOTNET_VERSION=10.0
RUN apt update && \
    apt install -y --no-install-recommends \
        dotnet-sdk-${DOTNET_VERSION} && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*
ENV DOTNET_CLI_HOME=${HOME}
ENV PATH="/usr/share/dotnet:${PATH}"

# --- Set Entrypoint ---
COPY --chmod=755 entrypoint.sh /usr/local/bin/container-entrypoint.sh

# --- Set User, Home directory and WORKDIR ---
USER ${USERNAME}
WORKDIR /app
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/container-entrypoint.sh"]
CMD ["/usr/bin/sleep", "infinity"]
