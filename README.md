# NEXWALL Installer Builder

Builds a bootable x86-64 hybrid ISO that contains the NEXWALL disk image and installs it onto an appliance's internal disk.

## Important assumptions

- The input is the released **`.img.gz`** (about 1 GiB when decompressed), or a raw `.img`. It is a **complete disk image** (partition table, partitions and bootloader included), not an update/package image.
- Target appliances are x86-64 and must boot in **UEFI**: the NEXWALL image itself does not boot on legacy BIOS, so a BIOS-only machine cannot run the installed system even if the installer starts.
- Installing overwrites the selected target disk completely. Back up anything important first.
- The ISO build requires a Debian 13 (trixie) amd64 build host with internet access and root/sudo access. The resulting ISO should be tested on the exact appliance model before deployment.

## Build

1. Copy the released image (`nexwall-26.1.1-x86-64-generic-squashfs-combined-efi.img.gz`) to the build host. Do not use the 32 GiB padded `.img` from the build output.
2. Run:

   ```bash
   sudo ./build-installer.sh nexwall-26.1.1-x86-64-generic-squashfs-combined-efi.img.gz 26.1.1
   ```

3. The output is `dist/NEXWALL-Installer-26.1.1.iso` and a companion `.sha256` file.
4. Write the ISO to a USB drive with Rufus. Boot the appliance from that USB.

The build script embeds the image and its SHA-256 in the live filesystem. The installer checks the embedded image before offering installation, excludes the live USB disk from the target list, requires typing `INSTALL`, checks that the target is large enough, writes the image, and reads the written bytes back from the disk (direct I/O) and compares their SHA-256.

## Language

The first screen asks for the language of the installer: English, Español or Português. Every message after it is shown in that language.

## Use

The same ISO serves every kind of target: attach it as a CD/DVD to a virtual machine, write it to a USB stick (Rufus in DD or ISO mode, balenaEtcher, `dd`), or use it from the remote console of an appliance.

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
