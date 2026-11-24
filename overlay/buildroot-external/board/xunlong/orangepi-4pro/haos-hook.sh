#!/bin/bash
# shellcheck disable=SC2155

# Hook HAOS per Orange Pi 4 Pro. Chiamato da scripts/post-image.sh.
# I blob del bootloader (boot0_sdcard.fex, boot_package.fex) arrivano da `build.sh bootloader`
# e sono montati nel container in /blobs (sudo ripulisce l'ambiente: non si puo' passare una variabile).

function haos_pre_image() {
    local BOOT_DATA="$(path_boot_dir)"
    local BLOBS="/blobs"
    local DTB="sun60i-a733-orangepi-4-pro.dtb"

    for f in boot0_sdcard.fex boot_package.fex; do
        if [ ! -s "${BLOBS}/${f}" ]; then
            echo "ERRORE: manca ${BLOBS}/${f}. Esegui prima: ./build.sh bootloader" >&2
            return 1
        fi
        cp "${BLOBS}/${f}" "${BINARIES_DIR}/${f}"
    done

    for f in Image "${DTB}" boot.scr; do
        if [ ! -s "${BINARIES_DIR}/${f}" ]; then
            echo "ERRORE: manca ${BINARIES_DIR}/${f}" >&2
            return 1
        fi
    done

    # Il U-Boot vendor legge kernel, dtb e script dalla partizione FAT 1
    cp "${BINARIES_DIR}/boot.scr" "${BOOT_DATA}/boot.scr"
    cp "${BINARIES_DIR}/Image" "${BOOT_DATA}/Image"
    cp "${BINARIES_DIR}/${DTB}" "${BOOT_DATA}/${DTB}"
    cp "${BOARD_DIR}/boot-env.txt" "${BOOT_DATA}/haos-config.txt"
    cp "${BOARD_DIR}/cmdline.txt" "${BOOT_DATA}/cmdline.txt"
}


function haos_post_image() {
    convert_disk_image_xz
}
