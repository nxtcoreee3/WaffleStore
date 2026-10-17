#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/WaffleStore.xcodeproj"
SCHEME="WaffleStore"
DERIVED_ROOT="${HOME}/Library/Developer/Xcode/DerivedData"

command -v xcodebuild >/dev/null || { echo "xcodebuild was not found. Install Xcode and select it with xcode-select." >&2; exit 1; }
test -d "$PROJECT" || { echo "Missing project: $PROJECT" >&2; exit 1; }
test -f "$ROOT/MapleSyrup/SAPKit/Package.swift" || { echo "Missing MapleSAP package." >&2; exit 1; }
test -f "$ROOT/MapleSyrup/Zsign/Package.swift" || { echo "Missing Zsign package." >&2; exit 1; }

echo "==> Cleaning this project's generated package/build state"
rm -rf "$ROOT/build/DerivedDataApp" "$ROOT/build/SourcePackages"
if [ -d "$DERIVED_ROOT" ]; then
  for dd in "$DERIVED_ROOT"/WaffleStore-*; do
    [ -d "$dd" ] && rm -rf "$dd"
  done
fi

echo "==> Resolving Swift packages"
xcodebuild \
  -resolvePackageDependencies \
  -project "$PROJECT" \
  -scheme "$SCHEME"

DD=""
if [ -d "$DERIVED_ROOT" ]; then
  DD="$(find "$DERIVED_ROOT" -maxdepth 1 -type d -name 'WaffleStore-*' -print -quit)"
fi

if [ -z "$DD" ]; then
  echo "Dependency resolution completed, but Xcode did not create a DerivedData package workspace." >&2
  exit 1
fi

for package in PartyUI Telegraph Zip CocoaAsyncSocket HTTPParserC OpenSSL; do
  test -d "$DD/SourcePackages/checkouts/$package" || {
    echo "Missing resolved checkout: $package" >&2
    exit 1
  }
done

test -d "$DD/SourcePackages/checkouts/OpenSSL/Frameworks/OpenSSL.xcframework" || {
  echo "Missing OpenSSL.xcframework in the resolved package workspace." >&2
  exit 1
}

echo "==> Dependencies installed and verified"
echo "Package workspace: $DD/SourcePackages"
echo "You can now open WaffleStore.xcodeproj and build."
