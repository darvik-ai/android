# Android Emulator Docker Container with Web GUI Access
# Base image with Ubuntu and desktop environment
FROM ubuntu:20.04

# Avoid interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Set environment variables
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=$ANDROID_HOME
ENV PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator
ENV DISPLAY=:99
ENV SCREEN_WIDTH=1024
ENV SCREEN_HEIGHT=768
ENV SCREEN_DEPTH=24

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Basic utilities
    curl \
    wget \
    unzip \
    git \
    vim \
    # Java Development Kit
    openjdk-8-jdk \
    # GUI and VNC dependencies
    xvfb \
    x11vnc \
    fluxbox \
    wmctrl \
    # Emulator dependencies
    qemu-kvm \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    cpu-checker \
    # NoVNC web interface
    python3 \
    python3-pip \
    python3-numpy \
    # Network utilities
    net-tools \
    netcat \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install ngrok
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-stable-linux-amd64.zip \
    && unzip ngrok-stable-linux-amd64.zip \
    && mv ngrok /usr/local/bin/ \
    && rm ngrok-stable-linux-amd64.zip

# Install NoVNC for web browser access
RUN mkdir -p /opt/novnc/utils/websockify \
    && wget -qO- https://github.com/novnc/noVNC/archive/v1.2.0.tar.gz | tar xz --strip 1 -C /opt/novnc \
    && wget -qO- https://github.com/novnc/websockify/archive/v0.9.0.tar.gz | tar xz --strip 1 -C /opt/novnc/utils/websockify \
    && ln -s /opt/novnc/vnc.html /opt/novnc/index.html

# Create Android SDK directory
RUN mkdir -p $ANDROID_HOME

# Download and install Android SDK Command Line Tools
RUN wget -q https://dl.google.com/android/repository/commandlinetools-linux-7583922_latest.zip -O /tmp/commandlinetools.zip \
    && unzip -q /tmp/commandlinetools.zip -d $ANDROID_HOME \
    && mv $ANDROID_HOME/cmdline-tools $ANDROID_HOME/cmdline-tools-temp \
    && mkdir -p $ANDROID_HOME/cmdline-tools/latest \
    && mv $ANDROID_HOME/cmdline-tools-temp/* $ANDROID_HOME/cmdline-tools/latest/ \
    && rm /tmp/commandlinetools.zip \
    && rm -rf $ANDROID_HOME/cmdline-tools-temp

# Update PATH for SDK tools
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin

# Accept Android SDK licenses
RUN yes | sdkmanager --licenses

# Install Android SDK components
RUN sdkmanager --update \
    && sdkmanager \
        "platform-tools" \
        "emulator" \
        "platforms;android-30" \
        "platforms;android-29" \
        "platforms;android-28" \
        "system-images;android-30;google_apis;x86_64" \
        "system-images;android-29;google_apis;x86_64" \
        "system-images;android-28;google_apis;x86_64"

# Create Android Virtual Device (AVD)
RUN echo "no" | avdmanager create avd \
    --name "android_emulator" \
    --package "system-images;android-30;google_apis;x86_64" \
    --device "pixel"

# Create startup script
RUN cat > /start.sh << 'EOF'
#!/bin/bash

# Function to cleanup on exit
cleanup() {
    echo "Shutting down services..."
    killall -TERM Xvfb x11vnc fluxbox emulator 2>/dev/null
    exit 0
}

# Set trap for cleanup
trap cleanup SIGTERM SIGINT

# Start Xvfb (Virtual Display)
echo "Starting Xvfb..."
Xvfb :99 -screen 0 ${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH} &
XVFB_PID=$!

# Wait for X server to start
sleep 2

# Start window manager
echo "Starting Fluxbox window manager..."
DISPLAY=:99 fluxbox &
FLUXBOX_PID=$!

# Start VNC server
echo "Starting VNC server..."
x11vnc -display :99 -nopw -listen localhost -xkb -ncache 10 -ncache_cr -forever -shared &
VNC_PID=$!

# Start noVNC web server
echo "Starting noVNC web server..."
cd /opt/novnc && python3 -m websockify.websockify --web . 6080 localhost:5900 &
NOVNC_PID=$!

# Wait for VNC to start
sleep 3

# Start Android Emulator
echo "Starting Android Emulator..."
DISPLAY=:99 emulator -avd android_emulator \
    -no-snapshot-save \
    -no-snapshot \
    -no-audio \
    -gpu swiftshader_indirect \
    -accel off \
    -skin 1080x1920 \
    -verbose &
EMULATOR_PID=$!

# Print access information
echo "==================================="
echo "Android Emulator is starting..."
echo "Web VNC access: http://localhost:6080"
echo "ADB port: 5554/5555"
echo "==================================="

# Start ngrok tunnel to port 6080
echo "Starting ngrok tunnel to port 6080..."
ngrok http 6080 --log=stdout > /var/log/ngrok.log 2>&1 &
NGROK_PID=$!
sleep 5

# Optional: Print public URL from ngrok API
NGROK_URL=$(curl --silent http://localhost:4040/api/tunnels | grep -o 'https://[a-z0-9]*\.ngrok.io')
echo "Ngrok public URL: $NGROK_URL"

# Wait for all processes
wait $XVFB_PID $FLUXBOX_PID $VNC_PID $NOVNC_PID $EMULATOR_PID
EOF

# Make startup script executable
RUN chmod +x /start.sh

# Expose ports
# 6080: noVNC web interface
# 5554: Emulator console port
# 5555: ADB port
EXPOSE 6080 5554 5555 4040

# Set working directory
WORKDIR /

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:6080 || exit 1

# Default command
CMD ["/start.sh"]
