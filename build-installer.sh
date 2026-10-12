#!/usr/bin/env bash
# Builds the NEXWALL installer ISO around a released disk image (.img.gz, or a raw .img).
set -Eeuo pipefail

usage() { echo "Usage: sudo $0 /path/to/nexwall-X.Y.Z-...-combined-efi.img.gz X.Y.Z" >&2; exit 2; }
[[ $# -eq 2 ]] || usage
INPUT=$(readlink -f "$1")
VERSION=$2
[[ -f "$INPUT" && -s "$INPUT" ]] || { echo "Input image not found or empty: $INPUT" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || { echo "Version must look like 26.1.1 or 26.1.1-rc1" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Run as root, e.g. sudo $0 image.img.gz 26.1.1" >&2; exit 1; }

for cmd in lb xorriso sha256sum gzip file; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing '$cmd'. On Debian: apt install live-build xorriso file" >&2; exit 1; }
done

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
PAYLOAD="$ROOT/config/includes.chroot/opt/nexwall-installer"
mkdir -p "$ROOT/dist"

DESC=$(file -b -z "$INPUT" 2>/dev/null || file -b "$INPUT")
if [[ "$DESC" == *"ISO 9660"* ]]; then
  echo "Input appears to be an ISO, not a disk image. Refusing." >&2; exit 1
fi

# The payload is stored compressed; the installer streams it to the disk and checks the SHA-256 of the decompressed bytes.
rm -f "$PAYLOAD/payload.img.gz"
if gzip -t "$INPUT" 2>/dev/null; then
  cp --reflink=auto "$INPUT" "$PAYLOAD/payload.img.gz"
else
  echo "Input is not gzip: compressing it (a raw image of several GiB takes a while)."
  gzip -9 -c "$INPUT" > "$PAYLOAD/payload.img.gz"
fi
SIZE=$(gzip -dc "$PAYLOAD/payload.img.gz" | wc -c)
SUM=$(gzip -dc "$PAYLOAD/payload.img.gz" | sha256sum | awk '{print $1}')
[[ "$SIZE" -gt 0 ]] || { echo "The image decompresses to nothing." >&2; exit 1; }
if (( SIZE > 8*1024*1024*1024 )); then
  echo "Warning: the decompressed image is $SIZE bytes. The released .img.gz is normally about 1 GiB; a padded disk image needs a target disk of the same size." >&2
fi
printf '%s\n' "$VERSION" > "$PAYLOAD/VERSION"
printf '%s\n' "$SUM" > "$PAYLOAD/SHA256SUM"
printf '%s\n' "$SIZE" > "$PAYLOAD/SIZE"

lb clean --purge || true
# Explicit settings (the build must not drift to another Debian release).
lb config \
  --distribution trixie \
  --parent-distribution trixie \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --archive-areas "main contrib non-free-firmware" \
  --debian-installer none \
  --firmware-chroot false \
  --firmware-binary false \
  --bootappend-live "boot=live components quiet"
grep -q 'LB_DISTRIBUTION="trixie"' config/bootstrap || { echo "live-build is not set to trixie" >&2; grep LB_DISTRIBUTION config/bootstrap >&2; exit 1; }
lb build

ISO=$(find "$ROOT" -maxdepth 1 -type f -name '*.iso' -printf '%p\n' | head -n1)
[[ -n "$ISO" && -s "$ISO" ]] || { echo "Build finished but no ISO was found in project root." >&2; exit 1; }
OUT="$ROOT/dist/NEXWALL-Installer-$VERSION.iso"
mv -f "$ISO" "$OUT"
( cd "$ROOT/dist" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
echo
echo "Build complete: $OUT"
echo "Checksum:      $OUT.sha256"
echo "Test this ISO (UEFI) before publishing it."
