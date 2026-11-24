#!/usr/bin/env bash
# build.sh build / shell / clean - compila l'immagine HAOS dentro il container di sviluppo ufficiale.

_docker() {
    if docker info >/dev/null 2>&1; then
        docker "$@"
    elif sudo -n docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
        sudo docker "$@"
    else
        die "docker non e' utilizzabile (daemon spento o permessi): esegui ./build.sh deps, poi rientra nella sessione"
    fi
}

_require_ready() {
    [ -d "${OS_DIR}/buildroot-external/board/xunlong/orangepi-4pro" ] || die "sorgenti non pronti: esegui ./build.sh fetch"
    { [ -s "${BLOBS_DIR}/boot0_sdcard.fex" ] && [ -s "${BLOBS_DIR}/boot_package.fex" ]; } \
        || die "blob bootloader mancanti: esegui ./build.sh bootloader"
}

_run_container() { # comando...
    mkdir -p "${CACHE_DIR}" "${OS_DIR}/output"
    local tty=()
    [ -t 0 ] && [ -t 1 ] && tty=(-it)
    _docker run --rm --privileged "${tty[@]}" \
        -v "${OS_DIR}:/build" \
        -v "${CACHE_DIR}:/cache" \
        -v "${BLOBS_DIR}:/blobs:ro" \
        -e BUILDER_UID="$(id -u)" -e BUILDER_GID="$(id -g)" \
        "${BUILDER_IMAGE}" "$@"
}

cmd_build() {
    local rebuild_image=1
    while [ $# -gt 0 ]; do
        case "$1" in
            --skip-image-build) rebuild_image=0; shift ;;
            *) die "opzione sconosciuta per build: $1" ;;
        esac
    done
    _require_ready

    if [ "${rebuild_image}" -eq 1 ] || ! _docker image inspect "${BUILDER_IMAGE}" >/dev/null 2>&1; then
        log "costruisco il container di build (${BUILDER_IMAGE})"
        _docker build -t "${BUILDER_IMAGE}" "${OS_DIR}"
    fi

    log "compilo ${BOARD_DEFCONFIG}: kernel Xunlong 6.6 + HAOS (1-4 ore la prima volta; la cache velocizza i rebuild)"
    local rc=0
    _run_container make "${BOARD_DEFCONFIG}" 2>&1 | tee "${WORK}/build.log" || rc="${PIPESTATUS[0]}"
    [ "${rc}" -eq 0 ] || die "build fallita (codice ${rc}): vedi ${WORK}/build.log (per indagare: ./build.sh shell)"

    local out="${WORK}/images" f found=0
    mkdir -p "${out}"
    for f in "${OS_DIR}"/output/images/haos_*.img*; do
        [ -e "${f}" ] || continue
        cp -f "${f}" "${out}/"; found=1
        log "immagine: ${out}/$(basename "${f}")"
    done
    [ "${found}" -eq 1 ] || die "nessuna immagine haos_*.img* in ${OS_DIR}/output/images"
    log "fatto. Prossimi passi: ./build.sh verify  e poi  ./flash.sh <immagine> /dev/sdX"
}

cmd_shell() {
    _require_ready
    _docker image inspect "${BUILDER_IMAGE}" >/dev/null 2>&1 || _docker build -t "${BUILDER_IMAGE}" "${OS_DIR}"
    _run_container bash
}

cmd_clean() {
    [ -d "${OS_DIR}" ] || { log "niente da pulire"; return 0; }
    log "rimuovo output di Buildroot (la cache dei download/ccache resta in ${CACHE_DIR})"
    if [ -d "${OS_DIR}/output" ]; then
        rm -rf "${OS_DIR}/output" 2>/dev/null || sudo rm -rf "${OS_DIR}/output"
    fi
}
