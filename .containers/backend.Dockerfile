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

# --- Set User, Home directory and WORKDIR ---
USER ${USERNAME}
WORKDIR /app
EXPOSE 8080
CMD ["/usr/bin/sleep", "infinity"]
