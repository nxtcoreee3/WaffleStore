#!/usr/bin/env bash
set -euo pipefail
# Xcode run-script phases use a restricted PATH. Homebrew installs cmake and
# Go under /opt/homebrew/bin on Apple Silicon, so add standard tool locations
# before invoking either native build script.
for tool_dir in /opt/homebrew/bin /usr/local/bin; do
  if [[ -d "$tool_dir" ]]; then
    case ":$PATH:" in
      *":$tool_dir:"*) ;;
      *) PATH="$tool_dir:$PATH" ;;
    esac
  fi
done
export PATH
cd "$(dirname "$0")/.."
case ${PLATFORM_NAME:-iphoneos} in
  iphoneos) NATIVE_PLATFORM=ios; NATIVE_SDK_NAME=iphoneos ;;
  iphonesimulator) NATIVE_PLATFORM=ios-simulator; NATIVE_SDK_NAME=iphonesimulator ;;
  *)
    echo "The native SAP library supports iphoneos and iphonesimulator only (got ${PLATFORM_NAME:-unset})." >&2
    exit 2
    ;;
esac
FINGERPRINT=$( { shasum -a 256 scripts/prepare-unicorn-tci.py scripts/build-unicorn-tci.sh scripts/build-sap-native.sh $(find MapleSyrup/NativeSAP -name "*.go" -type f | sort); printf '%s\n' "$NATIVE_PLATFORM"; xcrun --sdk "$NATIVE_SDK_NAME" --show-sdk-version; } | shasum -a 256 | cut -d ' ' -f 1)
if [[ -f build/Native/fingerprint && -f build/Native/libunicorn.a && -f build/Native/libWaffleSAP.a ]] && [[ $(cat build/Native/fingerprint) == "$FINGERPRINT" ]]; then
  exit 0
fi
NATIVE_SDK_NAME="$NATIVE_SDK_NAME" bash scripts/build-unicorn-tci.sh "$PWD/build/Native" "$NATIVE_PLATFORM"
NATIVE_SDK_NAME="$NATIVE_SDK_NAME" bash scripts/build-sap-native.sh
printf '%s\n' "$FINGERPRINT" > build/Native/fingerprint
