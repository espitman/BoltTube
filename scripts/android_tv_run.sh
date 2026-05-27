#!/bin/bash

set -euo pipefail

PROJECT_ROOT="/Users/espitman/Documents/Projects/BoltTube"
TV_APP_DIR="$PROJECT_ROOT/android-tv-app"
APK_PATH="$TV_APP_DIR/build/outputs/apk/debug/android-tv-app-debug.apk"
APP_ID="ir.boum.bolttube.tv"
MAIN_ACTIVITY="ir.boum.bolttube.tv.MainActivity"
REQUESTED_AVD="${1:-Android_TV_1080p_API_36}"
AVD_NAME=""

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
PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
GRADLE_OPTS="${GRADLE_OPTS:-} --add-exports=jdk.compiler/com.sun.tools.javac.main=ALL-UNNAMED"
export ANDROID_HOME ANDROID_SDK_ROOT JAVA_HOME GRADLE_OPTS

ADB_BIN="$ANDROID_SDK_ROOT/platform-tools/adb"
EMU_BIN="$ANDROID_SDK_ROOT/emulator/emulator"
AVD_RUNNING_DIR="$HOME/Library/Caches/TemporaryItems/avd/running"

echo "Starting Android TV debug build and launch for BoltTube..."
echo "Using JAVA_HOME=$JAVA_HOME"

if [ ! -x "$ADB_BIN" ]; then
  echo "Error: adb not found at $ADB_BIN"
  exit 1
fi

if [ ! -x "$EMU_BIN" ]; then
  echo "Error: emulator not found at $EMU_BIN"
  exit 1
fi

if [ ! -x "$TV_APP_DIR/gradlew" ]; then
  echo "Error: gradlew not found at $TV_APP_DIR/gradlew"
  exit 1
fi

SERIAL="$($ADB_BIN devices | awk '$1 ~ /^emulator-/ && $2 == "device" {print $1; exit}')"

if [ -z "$SERIAL" ]; then
  rm -rf "$AVD_RUNNING_DIR"
  rm -f "$HOME/.android/avd/$REQUESTED_AVD.avd/"*.lock "$HOME/.android/avd/$REQUESTED_AVD.avd/multiinstance.lock" 2>/dev/null || true

  AVAILABLE_AVDS="$("$EMU_BIN" -list-avds || true)"
  if [ -z "$AVAILABLE_AVDS" ]; then
    echo "Error: no Android AVD found. Create a TV AVD first."
    exit 1
  fi

  if echo "$AVAILABLE_AVDS" | grep -Fxq "$REQUESTED_AVD"; then
    AVD_NAME="$REQUESTED_AVD"
  else
    AVD_NAME="$(echo "$AVAILABLE_AVDS" | grep -Ei 'google-tv|android tv|tv|television' | head -1 || true)"
    if [ -z "$AVD_NAME" ]; then
      AVD_NAME="$(echo "$AVAILABLE_AVDS" | head -1)"
    fi
    echo "Requested AVD '$REQUESTED_AVD' not found. Using '$AVD_NAME'."
  fi

  echo "No online emulator found. Booting $AVD_NAME..."
  rm -f "$HOME/.android/avd/$AVD_NAME.avd/"*.lock "$HOME/.android/avd/$AVD_NAME.avd/multiinstance.lock" 2>/dev/null || true
  nohup "$EMU_BIN" -avd "$AVD_NAME" -gpu host -no-snapshot-load -no-boot-anim >/tmp/bolttube_android_tv_emulator.log 2>&1 &

  for _ in $(seq 1 180); do
    SERIAL="$($ADB_BIN devices | awk '$1 ~ /^emulator-/ && $2 == "device" {print $1; exit}')"
    if [ -n "$SERIAL" ]; then
      break
    fi
    sleep 2
  done
fi

if [ -z "${SERIAL:-}" ]; then
  echo "Error: emulator did not come online in time."
  "$ADB_BIN" devices -l || true
  exit 1
fi

echo "Target device: $SERIAL"
echo "Waiting for boot completion..."
"$ADB_BIN" -s "$SERIAL" wait-for-device
for _ in $(seq 1 120); do
  BOOT="$("$ADB_BIN" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
  if [ "$BOOT" = "1" ]; then
    break
  fi
  sleep 2
done

HOST_TIME_MS="$(($(date +%s) * 1000))"
"$ADB_BIN" -s "$SERIAL" shell cmd alarm set-time "$HOST_TIME_MS" >/dev/null 2>&1 || true

echo "Building Android TV debug APK..."
cd "$TV_APP_DIR"
if ! ./gradlew --no-daemon assembleDebug; then
  echo "Warning: debug build failed. Falling back to an existing debug APK if one is available."
fi

if [ ! -f "$APK_PATH" ]; then
  APK_PATH="$(find "$TV_APP_DIR/build/outputs/apk/debug" -name "*.apk" -type f | sort | tail -1)"
fi

if [ -z "${APK_PATH:-}" ] || [ ! -f "$APK_PATH" ]; then
  echo "Error: debug APK not found."
  exit 1
fi

echo "Installing debug APK..."
"$ADB_BIN" -s "$SERIAL" install -r -t "$APK_PATH"

echo "Launching $APP_ID/$MAIN_ACTIVITY..."
"$ADB_BIN" -s "$SERIAL" shell am start -W -n "$APP_ID/$MAIN_ACTIVITY"

echo "Android TV debug launch succeeded."
