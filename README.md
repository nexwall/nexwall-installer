# NEXWALL Installer Builder

Builds a bootable x86-64 hybrid ISO that contains a full-disk NEXWALL `.img` and installs it onto an appliance's internal disk.

## Important assumptions

- The input `.img` is a **raw, complete disk image** (partition table, partitions and bootloader included), not an update/package image.
- Target appliances are x86-64 and can boot a Debian Live ISO in UEFI or legacy mode.
- Installing overwrites the selected target disk completely. Back up anything important first.
- The ISO build requires a Debian 13 (trixie) amd64 build host with internet access and root/sudo access. The resulting ISO should be tested on the exact appliance model before deployment.

## Build

1. Copy the released image into this project directory, for example `NEXWALL-1.2.3.img`.
2. Run:

   ```bash
   sudo ./build-installer.sh NEXWALL-1.2.3.img 1.2.3
   ```

3. The output is `dist/NEXWALL-Installer-1.2.3.iso` and a companion `.sha256` file.
4. Write the ISO to a USB drive with Rufus. Boot the appliance from that USB.

The build script embeds the image and its SHA-256 in the live filesystem. The installer checks the embedded image before offering installation, excludes the live USB disk from the target list, requires typing `INSTALL`, checks that the target is large enough, writes the image, and hashes the written image bytes for read-back verification.

## Test checklist

- Test UEFI boot and legacy BIOS boot if both are supported by your appliances.
- Confirm the USB installation media is never listed as a destination.
- Test with at least one disposable disk; the chosen target disk is erased.
- Verify the installed system boots and its network interfaces are mapped as expected.
- Keep the source `.img`, ISO and checksums with the release artifacts.

## Troubleshooting

- If `lb` is missing, install the Debian `live-build` package.
- If package download/build fails, retry on a supported Debian 13 host with working DNS and internet access.
- If the installer finds no target disk, check that the appliance exposes the internal storage to Linux and that the disk is not removable.
- If the input image is larger than the target disk, use a larger disk; the installer will refuse to write it.
