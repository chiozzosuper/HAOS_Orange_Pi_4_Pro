-Native Home Assistant OS for Orange Pi 4 Pro (Allwinner A733, 4 GB)

HAOS image (no VM, no Docker on the board:, built on an x86_64 Ubuntu PC and flashed to a microSD card.

-Requirements
- Build PC: Ubuntu/Debrian/WSL, >= 80 GB free space, >= 8 GB RAM.
- Orange Pi 4 Pro 4 GB, 128 GB microSD
- Ethernet cable.


-Usage
```bash
# in downloaded git repository directory on the build PC
./build.sh deps          # once: packages, docker 
./build.sh all           # fetch + bootloader + build (1-4 hours) + verify
./flash.sh work/images/haos_orangepi-4pro-*.img.xz /dev/sdX
```
Individual steps: `fetch`, `bootloader`, `build`, `verify`, `shell`, `clean` (`./build.sh --help`).

If compiling vendor U-Boot fails on your PC, use an image that already boots on the board (Armbian/DietPi/Orange Pi, including `.img.xz`) as a bootloader donor:
```bash
./build.sh bootloader --force --from-image ~/Armbian_orangepi4pro.img.xz
```

Variables: `HAOS_TAG` (default `18.5`, or `latest`), `WORK_DIR` (default `./work`).

-Structure (deep modules: small interface, hidden details)
```
build.sh                      single entry point (deps|fetch|bootloader|build|verify|shell|clean|all)
flash.sh                      SD writing with safety checks and typed confirmation
lib/                          command implementation (not used directly)
overlay/buildroot-external/   files added to the HAOS repo at fetch time
  configs/orangepi_4pro_defconfig
  board/xunlong/orangepi-4pro/   meta, U-Boot boot script, hook, genimage fragments, kernel config
  patches-opi4pro/linux/         kernel patches (from Armbian + one for GCC 14 warnings)
patches/uboot/                vendor U-Boot patches
SERIAL.md                     serial console and first-boot diagnostics
```

Consequences to keep in mind:
- Updating **the operating system** from the UI does not work: to update the OS, rebuild and re-flash (data is on a separate partition, but make an HA backup first). Core, Supervisor, and add-ons update normally.
- `rauc-mark-good.service` may appear failed: expected, without A/B.
- The 3 HAOS kernel patches for 6.18 (ipv6, vlan, bluetooth) do not apply to 6.6 and are excluded.
- No built-in Wi-Fi/Bluetooth, GPU, or NPU. USB and Ethernet do work.


## Licenses and Provenance ##
`kernel-sun60iw2-vendor.config` and the patches in `patches-opi4pro/linux/` and `patches/uboot/` come from the Armbian project (GPL-2.0), at the commits indicated in `lib/common.sh`; the rest is an overlay for the `home-assistant/operating-system` repository (Apache-2.0). The `boot0`/`sys_config` blobs are Allwinner/Orange Pi binaries.
