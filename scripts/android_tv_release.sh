#!/bin/bash

set -euo pipefail

PROJECT_ROOT="/Users/espitman/Documents/Projects/BoltTube"
TV_APP_DIR="$PROJECT_ROOT/android-tv-app"
APK_PATH="$TV_APP_DIR/build/outputs/apk/release/android-tv-app-release.apk"
DESKTOP_DIR="$HOME/Desktop"
OUT_APK="$DESKTOP_DIR/bolttube-tv-release.apk"

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
  if [ -x "/opt/homebrew/opt/openjdk@17/bin/java" ]; then
    JAVA_HOME="/opt/homebrew/opt/openjdk@17"
  elif [ -x "/usr/local/opt/openjdk@17/bin/java" ]; then
    JAVA_HOME="/usr/local/opt/openjdk@17"
  elif [ -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" ]; then
    JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  elif [ -x "/Users/espitman/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" ]; then
    JAVA_HOME="/Users/espitman/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  else
    echo "Error: no usable Java 17 runtime found. Install OpenJDK 17 or set JAVA_HOME."
    exit 1
  fi
fi
PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
GRADLE_OPTS="${GRADLE_OPTS:-} --add-exports=jdk.compiler/com.sun.tools.javac.main=ALL-UNNAMED"
export ANDROID_HOME ANDROID_SDK_ROOT JAVA_HOME GRADLE_OPTS

echo "Building signed Android TV release APK for BoltTube..."
echo "Using JAVA_HOME=$JAVA_HOME"

if [ ! -x "$TV_APP_DIR/gradlew" ]; then
  echo "Error: gradlew not found at $TV_APP_DIR/gradlew"
  exit 1
fi

if [ ! -f "$TV_APP_DIR/release.jks" ]; then
  echo "Error: release keystore not found at $TV_APP_DIR/release.jks"
  exit 1
fi

BUILD_TOOLS_DIR="$(find "$ANDROID_SDK_ROOT/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)"
APKSIGNER="$BUILD_TOOLS_DIR/apksigner"

if [ ! -x "${APKSIGNER:-}" ]; then
  echo "Error: apksigner not found under $ANDROID_SDK_ROOT/build-tools"
  exit 1
fi

echo "Building release APK..."
cd "$TV_APP_DIR"
./gradlew --no-daemon assembleRelease

if [ ! -f "$APK_PATH" ]; then
  APK_PATH="$(find "$TV_APP_DIR/build/outputs/apk/release" -name "*.apk" -type f | sort | tail -1)"
fi

if [ -z "${APK_PATH:-}" ] || [ ! -f "$APK_PATH" ]; then
  echo "Error: release APK not found."
  exit 1
fi

echo "Verifying APK signature..."
"$APKSIGNER" verify --verbose --print-certs "$APK_PATH" >/tmp/bolttube-tv-release-verify.txt
cat /tmp/bolttube-tv-release-verify.txt

cp "$APK_PATH" "$OUT_APK"
echo "Release APK copied to $OUT_APK"

echo "Release build completed. Install the APK manually on the target Android TV device."
