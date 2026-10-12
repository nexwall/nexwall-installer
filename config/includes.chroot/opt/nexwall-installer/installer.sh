#!/bin/bash
set -Eeuo pipefail

APP_DIR=/opt/nexwall-installer
IMAGE="$APP_DIR/payload.img"
HASH_FILE="$APP_DIR/SHA256SUM"
VERSION_FILE="$APP_DIR/VERSION"
LOG=/var/log/nexwall-installer.log
exec > >(tee -a "$LOG") 2>&1

say() { whiptail --title "NEXWALL Installer" --msgbox "$1" 14 78; }
fail() { say "ERROR: $1\n\nLog: $LOG"; exit 1; }

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -t 0 ]] || { echo "Installer needs an interactive terminal (tty1)."; exit 1; }
[[ -f "$IMAGE" && -s "$IMAGE" ]] || fail "The NEXWALL image is missing or empty."
[[ -f "$HASH_FILE" && -f "$VERSION_FILE" ]] || fail "Release metadata is missing."
VERSION=$(tr -d '\r\n' < "$VERSION_FILE")
EXPECTED=$(awk 'NR==1 {print $1}' "$HASH_FILE")
[[ "$EXPECTED" =~ ^[a-fA-F0-9]{64}$ ]] || fail "The embedded SHA-256 value is invalid."

whiptail --title "NEXWALL Installer $VERSION" --yesno \
"This utility installs NEXWALL $VERSION to an internal disk.\n\nALL DATA on the selected target disk will be erased.\n\nContinue to disk selection?" 14 78 || exit 0

ACTUAL=$(sha256sum "$IMAGE" | awk '{print $1}')
[[ "${ACTUAL,,}" == "${EXPECTED,,}" ]] || fail "The embedded image failed SHA-256 verification. Do not install."
IMG_BYTES=$(stat -c '%s' "$IMAGE")

# Determine which physical disk hosts the live USB medium, then exclude it.
LIVE_SRC=$(findmnt -rn -o SOURCE /run/live/medium 2>/dev/null | head -n1 || true)
LIVE_DISK=""
if [[ -n "$LIVE_SRC" ]]; then
  LIVE_SRC=$(readlink -f "$LIVE_SRC" 2>/dev/null || printf '%s' "$LIVE_SRC")
  if [[ "$LIVE_SRC" == /dev/* && -b "$LIVE_SRC" ]]; then
    PARENT=$(lsblk -ndo PKNAME "$LIVE_SRC" 2>/dev/null | head -n1 || true)
    if [[ -n "$PARENT" ]]; then LIVE_DISK="/dev/$PARENT"; else LIVE_DISK="$LIVE_SRC"; fi
  fi
fi

# Also check the live mount's backing device in case /run/live/medium reports an alias.
if [[ -z "$LIVE_DISK" ]]; then
  LIVE_SRC=$(findmnt -rn -o SOURCE /run/live 2>/dev/null | head -n1 || true)
  if [[ "$LIVE_SRC" == /dev/* ]]; then
    LIVE_SRC=$(readlink -f "$LIVE_SRC" 2>/dev/null || printf '%s' "$LIVE_SRC")
    PARENT=$(lsblk -ndo PKNAME "$LIVE_SRC" 2>/dev/null | head -n1 || true)
    if [[ -n "$PARENT" ]]; then LIVE_DISK="/dev/$PARENT"; elif [[ -b "$LIVE_SRC" ]]; then LIVE_DISK="$LIVE_SRC"; fi
  fi
fi

MENU=()
while read -r NAME TYPE RM SIZE MODEL; do
  [[ "$TYPE" == disk ]] || continue
  [[ "$RM" == 0 ]] || continue
  [[ -b "$NAME" ]] || continue
  # Never offer the USB/live medium as a target.
  [[ -n "$LIVE_DISK" && "$(readlink -f "$NAME")" == "$(readlink -f "$LIVE_DISK")" ]] && continue
  BYTES=$(blockdev --getsize64 "$NAME" 2>/dev/null || echo 0)
  (( BYTES >= IMG_BYTES )) || continue
  LABEL="$NAME | $SIZE | ${MODEL:-disk}"
  MENU+=("$NAME" "$LABEL")
done < <(lsblk -dnpo NAME,TYPE,RM,SIZE,MODEL)

((${#MENU[@]} >= 2)) || fail "No eligible internal disk was found. Confirm the disk is detected, non-removable, and at least ${IMG_BYTES} bytes. The live USB is intentionally excluded."
TARGET=$(whiptail --title "Select target disk" --menu \
"Choose the internal disk to erase and install NEXWALL $VERSION onto.\n\nThe live USB is excluded. Only disks large enough for the image are shown." \
20 90 8 "${MENU[@]}" 3>&1 1>&2 2>&3) || exit 0
[[ -b "$TARGET" ]] || fail "Selected target is no longer available."
[[ -z "$LIVE_DISK" || "$(readlink -f "$TARGET")" != "$(readlink -f "$LIVE_DISK")" ]] || fail "Safety check blocked the live USB as a target."

TARGET_BYTES=$(blockdev --getsize64 "$TARGET")
(( TARGET_BYTES >= IMG_BYTES )) || fail "Target disk is smaller than the image."

whiptail --title "FINAL CONFIRMATION" --inputbox \
"You are about to ERASE ALL DATA on:\n\n$TARGET\n\nImage: NEXWALL $VERSION\nImage size: $IMG_BYTES bytes\n\nType exactly INSTALL to proceed." 18 78 3>&1 1>&2 2>&3 | grep -qx 'INSTALL' || exit 0

whiptail --title "Installing NEXWALL" --infobox \
"Writing NEXWALL $VERSION to $TARGET.\nDo not power off or remove the USB.\nProgress is being written to $LOG." 10 78
sync
# Unmount any mounted partitions on the target before writing the raw disk image.
while read -r PART; do
  [[ -n "$PART" ]] || continue
  umount "$PART" 2>/dev/null || true
done < <(lsblk -lnpo NAME "$TARGET" | tail -n +2)

set +e
dd if="$IMAGE" of="$TARGET" bs=16M iflag=fullblock conv=fsync status=progress
DD_RC=$?
set -e
(( DD_RC == 0 )) || fail "Writing the image failed (dd exit code $DD_RC). Do not remove power; review $LOG."
sync

# Hash exactly the source image length; the target disk may be larger than the image.
READBACK=$(head -c "$IMG_BYTES" "$TARGET" | sha256sum | awk '{print $1}')
[[ "${READBACK,,}" == "${EXPECTED,,}" ]] || fail "Read-back SHA-256 verification failed. Do not deploy this disk."

whiptail --title "Installation complete" --yesno \
"NEXWALL $VERSION was written and verified successfully.\n\nRemove the USB installation media, then choose Yes to reboot." 14 78
ANSWER=$?
if (( ANSWER == 0 )); then
  sync
  reboot
else
  say "Installation verified. You may now shut down, remove the USB, and boot from the internal disk."
fi
