#!/bin/bash
# NEXWALL interactive disk installer. Runs on tty1 of the live system.
set -Eeuo pipefail

APP_DIR=/opt/nexwall-installer
IMAGE="$APP_DIR/payload.img.gz"
HASH_FILE="$APP_DIR/SHA256SUM"      # SHA-256 of the DECOMPRESSED image
SIZE_FILE="$APP_DIR/SIZE"           # size in bytes of the decompressed image
VERSION_FILE="$APP_DIR/VERSION"
LOG=/var/log/nexwall-installer.log
TTY=/dev/tty1

: > "$LOG"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

# The dialogs talk to the console directly, so the log redirection never touches the screen.
W() { whiptail --title "NEXWALL Installer" "$@" 3>&1 1>"$TTY" 2>&3 <"$TTY"; }
say() { W --msgbox "$1" 14 78 || true; }
fail() { log "ERROR: $1"; say "ERROR: $1\n\nLog: $LOG"; exit 1; }

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
for f in "$IMAGE" "$HASH_FILE" "$SIZE_FILE" "$VERSION_FILE"; do
  [[ -s "$f" ]] || fail "Installer payload is incomplete ($f is missing or empty)."
done
VERSION=$(tr -d '\r\n' < "$VERSION_FILE")
EXPECTED=$(awk 'NR==1 {print tolower($1)}' "$HASH_FILE")
IMG_BYTES=$(tr -d '\r\n' < "$SIZE_FILE")
[[ "$EXPECTED" =~ ^[a-f0-9]{64}$ ]] || fail "The embedded SHA-256 value is invalid."
[[ "$IMG_BYTES" =~ ^[0-9]+$ ]] || fail "The embedded image size is invalid."
log "NEXWALL $VERSION, image $IMG_BYTES bytes, sha256 $EXPECTED"

W --yesno "This utility installs NEXWALL $VERSION on an internal disk.\n\nALL DATA on the disk you select will be erased.\n\nContinue to disk selection?" 14 78 || exit 0

# 1. Verify the payload before touching any disk.
W --infobox "Checking the installation image..." 7 60
gzip -t "$IMAGE" || fail "The embedded image is damaged (gzip test failed). Do not install."
ACTUAL=$(gzip -dc "$IMAGE" | sha256sum | awk '{print $1}')
[[ "$ACTUAL" == "$EXPECTED" ]] || fail "The embedded image failed SHA-256 verification. Do not install."
log "payload verified"

# 2. Find the disk the live medium runs from, so it is never offered.
LIVE_DISK=""
for MP in /run/live/medium /run/live /lib/live/mount/medium; do
  SRC=$(findmnt -rn -o SOURCE "$MP" 2>/dev/null | head -n1 || true)
  [[ "$SRC" == /dev/* ]] || continue
  SRC=$(readlink -f "$SRC")
  PARENT=$(lsblk -ndo PKNAME "$SRC" 2>/dev/null | head -n1 || true)
  LIVE_DISK=${PARENT:+/dev/$PARENT}
  LIVE_DISK=${LIVE_DISK:-$SRC}
  break
done
log "live disk: ${LIVE_DISK:-unknown}"

# 3. Eligible targets: whole, non-removable disks that are large enough.
MENU=()
while read -r NAME TYPE RM SIZE TRAN MODEL; do
  [[ "$TYPE" == disk && "$RM" == 0 && -b "$NAME" ]] || continue
  [[ -z "$LIVE_DISK" || "$(readlink -f "$NAME")" != "$LIVE_DISK" ]] || continue
  BYTES=$(blockdev --getsize64 "$NAME" 2>/dev/null || echo 0)
  (( BYTES >= IMG_BYTES )) || continue
  MENU+=("$NAME" "$SIZE ${TRAN:--} ${MODEL:-disk}")
done < <(lsblk -dnpo NAME,TYPE,RM,SIZE,TRAN,MODEL)

if [[ -z "$LIVE_DISK" ]]; then
  W --yesno "Warning: the installation USB could not be identified, so it is NOT excluded from the list. Check the disk names carefully.\n\nContinue?" 12 78 || exit 0
fi
((${#MENU[@]} >= 2)) || fail "No eligible internal disk was found. The disk must be detected, non-removable and at least $IMG_BYTES bytes. The installation USB is excluded."

TARGET=$(W --menu "Choose the disk to ERASE and install NEXWALL $VERSION on.\n\nThe installation USB is not listed." 20 90 8 "${MENU[@]}") || exit 0
[[ -b "$TARGET" ]] || fail "The selected disk is no longer available."
[[ -z "$LIVE_DISK" || "$(readlink -f "$TARGET")" != "$LIVE_DISK" ]] || fail "Safety check blocked the installation USB as a target."

ANSWER=$(W --inputbox "You are about to ERASE ALL DATA on:\n\n$TARGET\n\nNEXWALL $VERSION, $IMG_BYTES bytes.\n\nType INSTALL (capital letters) to proceed." 18 78 "") || exit 0
[[ "$ANSWER" == "INSTALL" ]] || exit 0

# 4. Write.
log "writing to $TARGET"
W --infobox "Writing NEXWALL $VERSION to $TARGET.\n\nDo not power off or remove the USB.\nThis takes a few minutes." 10 70
while read -r PART; do
  [[ -n "$PART" ]] && umount "$PART" 2>/dev/null || true
done < <(lsblk -lnpo NAME "$TARGET" | tail -n +2)
swapoff -a 2>/dev/null || true

set +e
gzip -dc "$IMAGE" | dd of="$TARGET" bs=16M iflag=fullblock oflag=direct conv=fsync status=none 2>>"$LOG"
RC=("${PIPESTATUS[@]}")
set -e
(( RC[0] == 0 && RC[1] == 0 )) || fail "Writing the image failed (gzip ${RC[0]}, dd ${RC[1]}). Review $LOG."
sync
blockdev --flushbufs "$TARGET" 2>/dev/null || true
udevadm settle 2>/dev/null || true

# 5. Read back from the disk itself (direct I/O, no page cache) and compare.
W --infobox "Verifying what was written to $TARGET..." 7 70
READBACK=$(dd if="$TARGET" bs=16M iflag=direct,count_bytes count="$IMG_BYTES" status=none 2>>"$LOG" | sha256sum | awk '{print $1}')
log "read-back sha256 $READBACK"
[[ "$READBACK" == "$EXPECTED" ]] || fail "Read-back verification failed. Do not deploy this disk."

if W --yesno "NEXWALL $VERSION was written and verified.\n\nRemove the USB installation media, then choose Yes to restart. The first start of the new system opens the setup wizard." 14 78; then
  sync; systemctl reboot
else
  say "Installation verified. You can power off, remove the USB and boot from the internal disk."
fi
