# Use Dockerify Android base image - adjust tag to Android 16 if available or closest version
FROM shmayro/dockerify-android:latest

# Set environment variables
ENV ANDROID_VERSION=16
ENV DEVICE="Google Pixel 10"

# Copy Instagram APK into image
# COPY Instagram.apk /tmp/

# Install Instagram APK during build
# RUN adb install /tmp/Instagram.apk || echo "ADB not ready at build time; will install at runtime"

# Expose ports for web access and adb
EXPOSE 8000 5555

# Start container with emulator and scrcpy web interface
CMD ["sh", "-c", "/android-entrypoint.sh && sleep infinity"]
