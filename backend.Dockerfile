# syntax=docker/dockerfile:1

# --- Base Image from ../base ---
ARG DEV_BASE_IMAGE
FROM ${DEV_BASE_IMAGE}

ARG USERNAME

# --- Install .NET 10 ---
USER root
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

# --- Install Node.js (node binary only, for ponytail hooks) ---
ARG NODE_VERSION=v24.22.2
ARG NODE_SHA256=361718c444e49af2ca5a110c83ba6a8901143f23ab285ebbef0341f391f482a9
RUN curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.gz" \
      -o /tmp/node.tar.gz && \
    echo "${NODE_SHA256}  /tmp/node.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/node.tar.gz -C /tmp "node-${NODE_VERSION}-linux-x64/bin/node" && \
    install -m 755 "/tmp/node-${NODE_VERSION}-linux-x64/bin/node" "${HOME}/.local/bin/node" && \
    rm -rf /tmp/node.tar.gz "/tmp/node-${NODE_VERSION}-linux-x64" && \
    node --version

# --- Settings ---
EXPOSE 8080
CMD ["/usr/bin/sleep", "infinity"]
