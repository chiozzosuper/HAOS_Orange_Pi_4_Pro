#!/usr/bin/env bash
# build.sh bootloader - produce work/blobs/{boot0_sdcard.fex,boot_package.fex}.
#
# Due modi:
#   (default)          compila il U-Boot vendor 2018.05 e lo impacchetta con gli strumenti
#                      Allwinner/Orange Pi (stessa ricetta di Armbian, riferimenti pinnati).
#   --from-image IMG   estrae boot0 + boot_package da un'immagine che sai gia' funzionare
#                      su questa scheda (Armbian/DietPi/Orange Pi, .img o .img.xz).
#
# I blob sono binari vendor (DRAM init, monitor/BL31): non c'e' modo di ricompilarli.

_sha_check() { # file sha256
    local got
    got="$(sha256sum "$1" | cut -d' ' -f1)"
    [ "${got}" = "$2" ] || die "sha256 errato per $(basename "$1"): atteso $2, ottenuto ${got}"
}

_fetch_armbian_blobs() {
    local dst="$1"
    mkdir -p "${dst}"
    log "scarico boot0 e sys_config della Orange Pi 4 Pro (Armbian @ ${ARMBIAN_REF:0:10})"
    curl -fsSL -o "${dst}/boot0_sdcard.fex" "${ARMBIAN_BLOBS_URL}/boot0_sdcard_orangepi4pro.fex"
    curl -fsSL -o "${dst}/sys_config.fex"   "${ARMBIAN_BLOBS_URL}/sys_config_orangepi.fex"
    _sha_check "${dst}/boot0_sdcard.fex" "${BOOT0_SHA256}"
    _sha_check "${dst}/sys_config.fex"   "${SYSCONFIG_SHA256}"
}

_fetch_uboot_src() {
    log "scarico U-Boot vendor @ ${UBOOT_REF:0:10}"
    rm -rf "${UBOOT_SRC}"
    git init -q "${UBOOT_SRC}"
    git -C "${UBOOT_SRC}" remote add origin "${UBOOT_REPO}"
    git -C "${UBOOT_SRC}" fetch -q --depth 1 origin "${UBOOT_REF}"
    git -C "${UBOOT_SRC}" checkout -q FETCH_HEAD
    local p
    for p in "${ROOT}"/patches/uboot/*.patch; do
        [ -e "${p}" ] || continue
        log "applico $(basename "${p}")"
        patch -d "${UBOOT_SRC}" -p1 --no-backup-if-mismatch < "${p}" >/dev/null \
            || die "patch U-Boot non applicabile: $(basename "${p}")"
    done
}

_build_uboot() {
    # Flag come in Armbian (post_config_uboot_target__sun60iw2_vendor_quirks) + -std=gnu11:
    # il codice del 2018 non compila con lo standard C23 di GCC 15.
    local kcflags="-std=gnu11 -fcommon -Wno-error -Wno-attributes -Wno-array-bounds -Wno-maybe-uninitialized -Wno-stringop-overflow -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types"
    local -a mk=(make -C "${UBOOT_SRC}" ARCH=arm CROSS_COMPILE="${UBOOT_CROSS}" "PWD=${UBOOT_SRC}"
                 "KCFLAGS=${kcflags}" "HOSTCFLAGS=-std=gnu11 -fcommon -O2")
    log "configuro ${UBOOT_DEFCONFIG}"
    "${mk[@]}" "${UBOOT_DEFCONFIG}" >/dev/null
    log "compilo U-Boot (pochi minuti)"
    "${mk[@]}" -j"$(nproc)" >"${WORK}/uboot-build.log" 2>&1 \
        || { tail -n 40 "${WORK}/uboot-build.log" >&2; die "build U-Boot fallita (log completo: ${WORK}/uboot-build.log). Alternativa: ./build.sh bootloader --from-image <immagine funzionante>"; }
    [ -s "${UBOOT_SRC}/u-boot.bin" ] || die "u-boot.bin non prodotto"
}

_pack_uboot() {
    local blobs="$1" tmp pack
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN
    pack="${tmp}/opibuild/external/packages/pack-uboot"

    log "scarico gli strumenti pack-uboot (orangepi-build @ ${OPIBUILD_REF:0:10})"
    git init -q "${tmp}/opibuild"
    git -C "${tmp}/opibuild" remote add origin "${OPIBUILD_REPO}"
    git -C "${tmp}/opibuild" config core.sparseCheckout true
    echo "external/packages/pack-uboot/*" > "${tmp}/opibuild/.git/info/sparse-checkout"
    git -C "${tmp}/opibuild" fetch -q --depth 1 origin "${OPIBUILD_REF}"
    git -C "${tmp}/opibuild" checkout -q FETCH_HEAD
    { [ -d "${pack}/sun60iw2/bin" ] && [ -d "${pack}/tools" ]; } || die "layout pack-uboot inatteso in orangepi-build @ ${OPIBUILD_REF}"
    chmod +x "${pack}"/tools/* 2>/dev/null || true

    local run=(env -u QEMU_CPU -C "${tmp}")
    log "impacchetto boot_package.fex"
    cp -r "${pack}/sun60iw2/bin/." "${tmp}/"
    cp "${UBOOT_SRC}/u-boot.bin" "${tmp}/u-boot.fex"

    local dtc="${UBOOT_SRC}/scripts/dtc/dtc"
    "${dtc}" --version >/dev/null 2>&1 || dtc="$(command -v dtc)"
    "${dtc}" -p 2048 -W no-unit_address_vs_reg -@ -O dtb -o "${tmp}/uboot.dtb" -b 0 "${tmp}/dts/u-boot-current.dts"
    cp "${tmp}/uboot.dtb" "${tmp}/sunxi.fex"
    "${run[@]}" "${pack}/tools/update_dtb" sunxi.fex 4096

    cp "${blobs}/sys_config.fex" "${tmp}/sys_config.fex"
    sed -i 's/$/\r/' "${tmp}/sys_config.fex"
    "${run[@]}" "${pack}/tools/script" sys_config.fex

    "${run[@]}" "${pack}/tools/update_uboot" -no_merge u-boot.fex sys_config.bin
    sed -i 's/$/\r/' "${tmp}/boot_package.cfg"
    "${run[@]}" "${pack}/tools/dragonsecboot" -pack boot_package.cfg

    [ -s "${tmp}/boot_package.fex" ] || die "boot_package.fex non prodotto dal pack"
    cp "${tmp}/boot_package.fex" "${blobs}/boot_package.fex"
}

_from_source() {
    check_x86_64
    need_cmd git make gcc curl patch sha256sum xxd bison flex dtc "${UBOOT_CROSS}gcc"
    local stage="${WORK}/blobs-stage"
    rm -rf "${stage}"; mkdir -p "${stage}"
    _fetch_armbian_blobs "${stage}"
    _fetch_uboot_src
    _build_uboot
    _pack_uboot "${stage}"
    mkdir -p "${BLOBS_DIR}"
    cp "${stage}/boot0_sdcard.fex" "${stage}/boot_package.fex" "${BLOBS_DIR}/"
    rm -rf "${stage}"
}

_from_image() {
    local img="$1" tmp=""
    [ -f "${img}" ] || die "immagine non trovata: ${img}"
    need_cmd python3
    case "${img}" in
        *.xz) need_cmd xz; tmp="$(mktemp -p "${WORK}" donor.XXXXXX.img)"
              log "decomprimo ${img}"; xz -dc "${img}" > "${tmp}"; img="${tmp}" ;;
    esac
    mkdir -p "${BLOBS_DIR}"
    python3 - "${img}" "${BLOBS_DIR}" "${BOOT0_OFFSET_KIB}" "${BOOTPKG_OFFSET_KIB}" "${SPL_AREA_MIB}" <<'PY'
import struct, sys
img, out, b0_kib, bp_kib, area_mib = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
b0, bp, area = b0_kib * 1024, bp_kib * 1024, area_mib * 1024 * 1024
with open(img, "rb") as f:
    mbr = f.read(512)
    if mbr[510:512] != b"\x55\xaa":
        sys.exit("ERRORE: l'immagine non ha una tabella MBR (firma 55AA assente): non e' una immagine Allwinner con boot0 a 8 KiB")
    starts = [struct.unpack_from("<I", mbr, 446 + 16 * i + 8)[0] * 512 for i in range(4)
              if mbr[446 + 16 * i + 4] != 0]
    limit = min([area] + [s for s in starts if s > 0])
    if limit < bp + 64 * 1024:
        sys.exit("ERRORE: la prima partizione dell'immagine parte a %d KiB, troppo presto per boot_package a %d KiB" % (limit // 1024, bp_kib))
    f.seek(b0); boot0 = f.read(bp - b0)
    f.seek(bp); bpkg = f.read(limit - bp)
if boot0[4:12] != b"eGON.BT0":
    sys.exit("ERRORE: magic 'eGON.BT0' assente a 8 KiB: boot0 non trovato nell'immagine")
if not any(bpkg[:4096]):
    sys.exit("ERRORE: boot_package vuoto a %d KiB" % bp_kib)
open(out + "/boot0_sdcard.fex", "wb").write(boot0)
open(out + "/boot_package.fex", "wb").write(bpkg)
print("boot0: %d byte, boot_package: %d byte (fino a %d KiB)" % (len(boot0), len(bpkg), limit // 1024))
PY
    [ -z "${tmp}" ] || rm -f "${tmp}"
}

cmd_bootloader() {
    local from_image="" force=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --from-image) [ $# -ge 2 ] || die "--from-image richiede un percorso"; from_image="$2"; shift 2 ;;
            --force) force=1; shift ;;
            *) die "opzione sconosciuta per bootloader: $1" ;;
        esac
    done
    mkdir -p "${WORK}"
    if [ "${force}" -eq 0 ] && [ -s "${BLOBS_DIR}/boot0_sdcard.fex" ] && [ -s "${BLOBS_DIR}/boot_package.fex" ]; then
        log "blob gia' presenti in ${BLOBS_DIR} (usa --force per rifarli)"
        return 0
    fi
    rm -f "${BLOBS_DIR}/boot0_sdcard.fex" "${BLOBS_DIR}/boot_package.fex"
    if [ -n "${from_image}" ]; then _from_image "${from_image}"; else _from_source; fi
    ( cd "${BLOBS_DIR}" && sha256sum boot0_sdcard.fex boot_package.fex | tee SHA256SUMS >&2 )
    log "bootloader pronto in ${BLOBS_DIR}"
}
