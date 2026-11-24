#!/usr/bin/env bash
# shellcheck disable=SC2034
# Non eseguire direttamente.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK_DIR:-${ROOT}/work}"
OS_DIR="${WORK}/operating-system"
BLOBS_DIR="${WORK}/blobs"
CACHE_DIR="${WORK}/cache"
UBOOT_SRC="${WORK}/u-boot-orangepi"
OVERLAY_DIR="${ROOT}/overlay"

BOARD_DEFCONFIG="orangepi_4pro"
BUILDER_IMAGE="haos-builder-opi4pro"

# --- HAOS: tag da compilare (default: ultima stabile verificata; "latest" = ultimo tag N.N) ---
HAOS_REPO="https://github.com/home-assistant/operating-system.git"
HAOS_TAG="${HAOS_TAG:-18.5}"

# --- Bootloader Allwinner sun60iw2 ---
UBOOT_REPO="https://github.com/orangepi-xunlong/u-boot-orangepi.git"
UBOOT_REF="b791be842935b27268ae3d00e943a9075495f30a"      # branch v2018.05-sun60iw2
UBOOT_DEFCONFIG="sun60iw2p1_t736_defconfig"
UBOOT_CROSS="arm-linux-gnueabi-"                           # il U-Boot vendor e' ARM 32 bit
OPIBUILD_REPO="https://github.com/orangepi-xunlong/orangepi-build.git"
OPIBUILD_REF="7f776a209b72b92e8c6a06abc83b1e7597eef5af"   # strumenti pack-uboot
ARMBIAN_REF="1ce67c25929fc5b0c4b51d4c051ed7d7e156e8fd"
ARMBIAN_BLOBS_URL="https://raw.githubusercontent.com/armbian/build/${ARMBIAN_REF}/packages/blobs/sunxi/sun60iw2"
BOOT0_SHA256="9213f1c56ef932930d43b5751e8937bea0e9ae7460ec16187cc1b0dffdb75345"
SYSCONFIG_SHA256="eb598823d947fa39d0cf2102051b921d10f41b26538103b9fa3a266c6a486a29"

# Offset sulla SD 
BOOT0_OFFSET_KIB=8
BOOTPKG_OFFSET_KIB=16400
SPL_AREA_MIB=32

if [ -t 2 ]; then C_B=$'\e[1m'; C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_0=$'\e[0m'; else C_B=; C_R=; C_G=; C_Y=; C_0=; fi

log()  { printf '%s==>%s %s\n' "${C_G}${C_B}" "${C_0}" "$*" >&2; }
warn() { printf '%sWARN:%s %s\n' "${C_Y}${C_B}" "${C_0}" "$*" >&2; }
die()  { printf '%sERRORE:%s %s\n' "${C_R}${C_B}" "${C_0}" "$*" >&2; exit 1; }

need_cmd() {
    local c
    for c in "$@"; do
        command -v "${c}" >/dev/null 2>&1 || die "comando mancante: ${c} (esegui ./build.sh deps)"
    done
}

# Risolve HAOS_TAG=latest nell'ultimo tag stabile N.N
resolve_haos_tag() {
    if [ "${HAOS_TAG}" = "latest" ]; then
        need_cmd git sort
        HAOS_TAG="$(git ls-remote --tags --refs "${HAOS_REPO}" \
            | sed 's#.*refs/tags/##' | grep -E '^[0-9]+\.[0-9]+$' | sort -V | tail -1)"
        [ -n "${HAOS_TAG}" ] || die "impossibile determinare l'ultimo tag HAOS"
        log "ultimo tag HAOS stabile: ${HAOS_TAG}"
    fi
}

check_x86_64() {
    [ "$(uname -m)" = "x86_64" ] || die "serve un PC x86_64 (rilevato $(uname -m)): gli strumenti di pack Allwinner sono binari x86_64"
}
