#!/bin/sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/BoltTube.xcodeproj"
BUILD_DIR="${ROOT_DIR}/build"

xcodegen generate --spec "${ROOT_DIR}/project.yml"

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme BoltTube \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  build

APP_PATH="${BUILD_DIR}/Build/Products/Release/BoltTube.app"
echo "Built app: ${APP_PATH}"
