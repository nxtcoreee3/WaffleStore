#!/usr/bin/env bash
set -euo pipefail
# Xcode run-script phases inherit a minimal PATH, so make the Go toolchain
# discoverable from its usual install locations before it is first used.
for toolchain_dir in /opt/homebrew/bin /usr/local/go/bin /usr/local/bin "$HOME/go/bin"; do
  if [[ -x "$toolchain_dir/go" ]]; then
    case ":$PATH:" in
      *":$toolchain_dir:"*) ;;
      *) PATH="$toolchain_dir:$PATH" ;;
    esac
  fi
done
export PATH
if ! command -v go >/dev/null 2>&1; then
  echo 'error: Go is required to build the native SAP library; install it (for example "brew install go") and rebuild.' >&2
  exit 1
fi
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT="$ROOT/build/Native"
mkdir -p "$OUTPUT"
# Xcode sandboxes the user's home-directory caches. Keep all Go writes inside
# the project so the run-script phase can build without extra permissions.
export GOPATH="${GOPATH:-$ROOT/.work/gopath}"
export GOMODCACHE="${GOMODCACHE:-$GOPATH/pkg/mod}"
export GOCACHE="${GOCACHE:-$ROOT/.work/gocache}"
mkdir -p "$GOPATH" "$GOMODCACHE" "$GOCACHE"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# Reuse the current SAP guest, loader and shims only, with an isolated C ABI.
# All downloaded source and generated modifications are retained for review.
curl -fL --retry 3 https://github.com/majd/ipatool/archive/3411d57f451f5111ae115641c22f7ed17bbd5fbe.tar.gz -o "$WORK/ipatool.tar.gz"
python3 - "$WORK/ipatool.tar.gz" <<'PY'
import sys,hashlib
with open(sys.argv[1], 'rb') as f: digest=hashlib.sha256(f.read()).hexdigest()
if digest != '5c940788df3b619b07ead5e592b5a06beecd96ccdb7570f4fbd09a02b41785b7':
    raise SystemExit('ipatool source integrity mismatch')
PY
tar -xzf "$WORK/ipatool.tar.gz" -C "$WORK"
SOURCE="$WORK/ipatool-3411d57f451f5111ae115641c22f7ed17bbd5fbe"
mkdir -p "$SOURCE/wafflebridge"
cp "$ROOT/MapleSyrup/NativeSAP/main.go" "$SOURCE/wafflebridge/main.go"
mkdir -p "$SOURCE/wafflebridge/packageipa"
cp "$ROOT/MapleSyrup/NativeSAP/packageipa/"*.go "$SOURCE/wafflebridge/packageipa/"
python3 - "$SOURCE" <<'PY'
import pathlib,sys
root=pathlib.Path(sys.argv[1])
for name in ['assets.go','storeagent.go']:
    path=root/'internal/sap/assets'/name
    source=path.read_text()
    old='root, err := os.UserCacheDir()\n\tif err != nil {'
    if source.count(old)!=1: raise SystemExit('Unexpected SAP cache layout')
    source=source.replace(old,'root := CacheRoot\n\tvar err error\n\tif root == "" { err = errors.New("explicit sandbox cache path is required") }\n\tif err != nil {')
    if '"errors"' not in source: source=source.replace('import (', 'import (\n\t"errors"', 1)
    # os is still used for actual cache I/O, so the existing import stays.
    if name=='assets.go': source += '\n// Configured once by the sandboxed C bridge before any asset load.\nvar CacheRoot string\n'
    path.write_text(source)
PY
SDK_NAME=${NATIVE_SDK_NAME:-iphoneos}
SDK=$(xcrun --sdk "$SDK_NAME" --show-sdk-path)
CLANG=$(xcrun --sdk "$SDK_NAME" --find clang)
TARGET_TRIPLE=arm64-apple-ios16.4
if [[ "$SDK_NAME" == iphonesimulator ]]; then
  TARGET_TRIPLE=arm64-apple-ios16.4-simulator
fi
cd "$SOURCE"
GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$CLANG" SDKROOT="$SDK" \
  CGO_CFLAGS="-isysroot $SDK -target $TARGET_TRIPLE" \
  CGO_LDFLAGS="-isysroot $SDK -target $TARGET_TRIPLE" \
  go build -buildmode=c-archive -trimpath -o "$OUTPUT/libWaffleSAP.a" ./wafflebridge
go list -deps -json ./wafflebridge > "$WORK/dependencies.json"
python3 - "$WORK/dependencies.json" "$OUTPUT/GoThirdPartyNotices.txt" "$(go env GOROOT)" <<'PY'
import json,pathlib,sys
text=pathlib.Path(sys.argv[1]).read_text(); decoder=json.JSONDecoder(); modules={}
while text.strip():
    value,end=decoder.raw_decode(text.lstrip()); text=text.lstrip()[end:]
    module=value.get('Module')
    if module and module.get('Dir'): modules[module['Path']]=pathlib.Path(module['Dir'])
# GOROOT holds the Go LICENSE for the official tarball layout, while packaged
# distributions (for example Homebrew) keep it in the enclosing prefix.
goroot=pathlib.Path(sys.argv[3]).resolve()
for license_path in (goroot/'LICENSE', goroot.parent/'LICENSE', pathlib.Path('/usr/local/go/LICENSE')):
    if license_path.is_file():
        pieces=['Go standard library\n'+license_path.read_text()]
        break
else:
    raise SystemExit('Missing Go standard library license for GOROOT: '+str(goroot))
for name,root in sorted(modules.items()):
    found=[]
    for path in sorted(root.iterdir()):
        if path.is_file() and path.name.upper().startswith(('LICENSE','COPYING','NOTICE')):
            found.append(path.name+'\n'+path.read_text(errors='replace'))
    if not found: raise SystemExit('Missing license notice for linked module: '+name)
    pieces.append(name+'\n'+'\n'.join(found))
pathlib.Path(sys.argv[2]).write_text('\n\n'.join(pieces))
PY
cp "$OUTPUT/libWaffleSAP.h" "$OUTPUT/SAP-generated-ABI.h"
cp "$SOURCE/LICENSE" "$OUTPUT/IPATOOL-LICENSE"
tar -czf "$OUTPUT/ipatool-sap-corresponding-source.tar.gz" -C "$WORK" "$(basename "$SOURCE")"
echo 'Built SAP guest library (not the ipatool CLI).'
