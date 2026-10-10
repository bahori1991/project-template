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

# --- Set User and Workdir ---
USER ${USERNAME}
WORKDIR /app

# --- Install .NET global tools (easy-dotnet etc.) ---
ENV PATH="${HOME}/.dotnet/tools:/usr/share/dotnet:${PATH}"
RUN dotnet tool install -g EasyDotnet

# --- Settings ---
EXPOSE 8080
CMD ["/usr/bin/sleep", "infinity"]
