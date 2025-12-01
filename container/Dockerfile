FROM rust:latest

# set environment variables for tzdata
ARG TZ=America/New_York
ENV TZ=${TZ}

# --- Core build tools and dependencies for Aspen ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    pkg-config \
    libssl-dev \
    lldb \
    strace \
    iproute2 \
    linux-perf \
    man \
    make \
    curl \
    ca-certificates \
    locales \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /home

CMD ["/bin/bash"]