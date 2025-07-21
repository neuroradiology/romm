# trunk-ignore-all(trivy)
# trunk-ignore-all(checkov)

FROM ubuntu:22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Create non-root user first
RUN groupadd -r romm && useradd -r -g romm -d /home/romm -s /bin/bash romm \
    && mkdir -p /home/romm \
    && chown -R romm:romm /home/romm

# Install system dependencies (as root - this is necessary)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    make \
    gcc \
    g++ \
    libmariadb3 \
    libmariadb-dev \
    libpq-dev \
    libffi-dev \
    musl-dev \
    curl \
    ca-certificates \
    libmagic-dev \
    p7zip \
    tzdata \
    libbz2-dev \
    libssl-dev \
    libreadline-dev \
    libsqlite3-dev \
    zlib1g-dev \
    liblzma-dev \
    libncurses5-dev \
    libncursesw5-dev \
    sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install nvm for the non-root user
ENV NVM_DIR="/home/romm/.nvm"
RUN mkdir -p $NVM_DIR \
    && chown -R romm:romm $NVM_DIR
USER romm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install 18.20.8 \
    && nvm use 18.20.8 \
    && nvm alias default 18.20.8
ENV PATH="$NVM_DIR/versions/node/v18.20.8/bin:$PATH"

# Switch back to root for system operations
USER root

# Build and install RAHasher (needs to be in system location)
RUN git clone --recursive --branch 1.8.1 --depth 1 https://github.com/RetroAchievements/RALibretro.git /tmp/RALibretro
WORKDIR /tmp/RALibretro
RUN sed -i '22a #include <ctime>' ./src/Util.h \
    && sed -i '6a #include <unistd.h>' \
      ./src/libchdr/deps/zlib-1.3.1/gzlib.c \
      ./src/libchdr/deps/zlib-1.3.1/gzread.c \
      ./src/libchdr/deps/zlib-1.3.1/gzwrite.c \
    && make HAVE_CHD=1 -f ./Makefile.RAHasher \
    && cp ./bin64/RAHasher /usr/bin/RAHasher \
    && chmod +x /usr/bin/RAHasher
RUN rm -rf /tmp/RALibretro

# Create app directory with proper ownership
RUN mkdir -p /app && chown -R romm:romm /app

# Install uv for the non-root user
COPY --from=ghcr.io/astral-sh/uv:0.7.19 /uv /uvx /usr/local/bin/

# Switch to non-root user for application operations
USER romm
WORKDIR /app

# Install Python
RUN uv python install 3.13

# Copy and install Python dependencies
COPY --chown=romm:romm pyproject.toml uv.lock* .python-version /app/
RUN uv sync --all-extras

# Install frontend dependencies
COPY --chown=romm:romm frontend/package.json /app/frontend/
WORKDIR /app/frontend
RUN npm install

# Back to app directory
WORKDIR /app

# Copy entrypoint script and set permissions
USER root
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown romm:romm /entrypoint.sh

# Final switch to non-root user
USER romm

ENTRYPOINT ["/entrypoint.sh"]
