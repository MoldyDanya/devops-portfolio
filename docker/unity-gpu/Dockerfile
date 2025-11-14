FROM unityci/editor:ubuntu-2022.3.40f1-android-3.1.0

# Install GPU support and essential tools only
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libnvidia-gl-470 \
      xvfb \
      openbox \
      netcat-openbsd \
      adwaita-icon-theme-full \
      strace \
      gdb \
      x11-utils \
      x11-xserver-utils \
      imagemagick \
      xdotool \
      scrot \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Enable GPU support
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics

# Create directories
RUN mkdir -p /workspace /project/AltTesterLogs \
    && chmod 777 /workspace /project/AltTesterLogs

WORKDIR /workspace

EXPOSE 13000
CMD ["/bin/bash"]

