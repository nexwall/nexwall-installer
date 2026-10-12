#!/usr/bin/env bash
set -Eeuo pipefail

usage() { echo "Usage: sudo $0 /path/to/NEXWALL-X.Y.Z.img X.Y.Z" >&2; exit 2; }
[[ $# -eq 2 ]] || usage
INPUT=$(readlink -f "$1")
VERSION=$2
[[ -f "$INPUT" && -s "$INPUT" ]] || { echo "Input image not found or empty: $INPUT" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || { echo "Version must look like 1.2.3 or 1.2.3-rc1" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Run as root, e.g. sudo $0 image.img 1.2.3" >&2; exit 1; }

for cmd in lb xorriso sha256sum; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing '$cmd'. On Debian: apt install live-build xorriso" >&2; exit 1; }
done

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
PAYLOAD="$ROOT/config/includes.chroot/opt/nexwall-installer"
mkdir -p "$ROOT/dist"

# Refuse to accidentally package an ISO/image as the raw disk payload.
FILE_DESC=$(file -b "$INPUT" 2>/dev/null || true)
if [[ "$FILE_DESC" == *"ISO 9660"* ]]; then
  echo "Input appears to be an ISO, not a raw disk .img. Refusing." >&2; exit 1
fi

cp --reflink=auto "$INPUT" "$PAYLOAD/payload.img"
printf '%s\n' "$VERSION" > "$PAYLOAD/VERSION"
sha256sum "$PAYLOAD/payload.img" | awk '{print $1}' > "$PAYLOAD/SHA256SUM"

# Use a reproducible Debian Live configuration, with an ISO that can also be written as USB media.
if [[ ! -f config/auto/config ]]; then
  mkdir -p config/auto
  cat > config/auto/config <<'CONFIG'
#!/bin/sh
set -e
lb config noauto \
  --distribution trixie \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --archive-areas "main contrib non-free-firmware" \
  --debian-installer false \
  --bootappend-live "boot=live components quiet"
CONFIG
  chmod +x config/auto/config
fi

# Clean generated build state, but preserve the release payload and source configuration.
lb clean --purge || true
lb config
lb build

ISO=$(find "$ROOT" -maxdepth 1 -type f -name '*.iso' -printf '%p\n' | head -n1)
[[ -n "$ISO" && -s "$ISO" ]] || { echo "Build finished but no ISO was found in project root." >&2; exit 1; }
OUT="$ROOT/dist/NEXWALL-Installer-$VERSION.iso"
mv -f "$ISO" "$OUT"
sha256sum "$OUT" > "$OUT.sha256"
echo
echo "Build complete: $OUT"
echo "Checksum:      $OUT.sha256"
echo "Test this ISO on the target appliance before production deployment."
