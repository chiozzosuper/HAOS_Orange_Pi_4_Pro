#!/usr/bin/env bash
# build.sh fetch

apply_overlay() {
    local be="${OS_DIR}/buildroot-external"
    [ -d "${be}/kernel/v6.18.y" ] || die "il tag ${HAOS_TAG} non ha kernel/v6.18.y: il layout e' cambiato, aggiorna l'overlay"
    [ -d "${be}/board/hardkernel/odroid-c4" ] || warn "board di riferimento odroid-c4 assente in ${HAOS_TAG}"

    log "applico overlay (board xunlong/orangepi-4pro, defconfig, patch kernel)"
    rsync -a "${OVERLAY_DIR}/buildroot-external/" "${be}/"

    # scritte per 6.18, non applicabili al kernel vendor 6.6
    
    local d n
    for d in "${be}"/patches/*/; do
        n="$(basename "${d}")"
        [ "${n}" = "linux" ] && continue
        ln -sfn "../patches/${n}" "${be}/patches-opi4pro/${n}"
    done

    # hdd-image.sh fissa KERNEL_SIZE=24M
    local hdd="${be}/scripts/hdd-image.sh"
    if grep -q '^KERNEL_SIZE=24M$' "${hdd}"; then
        sed -i 's/^KERNEL_SIZE=24M$/KERNEL_SIZE=\${KERNEL_SIZE:-24M}/' "${hdd}"
    fi
    grep -qF 'KERNEL_SIZE=${KERNEL_SIZE:-24M}' "${hdd}" || die "patch di hdd-image.sh non applicata (layout cambiato?)"

    chmod +x "${be}/board/xunlong/orangepi-4pro/haos-hook.sh"
}

cmd_fetch() {
    need_cmd git rsync
    resolve_haos_tag
    mkdir -p "${WORK}"

    if [ -d "${OS_DIR}/.git" ]; then
        local cur
        cur="$(git -C "${OS_DIR}" describe --tags --exact-match 2>/dev/null || true)"
        [ "${cur}" = "${HAOS_TAG}" ] || die "${OS_DIR} e' al tag '${cur:-?}', richiesto ${HAOS_TAG}: rimuovilo o cambia WORK_DIR"
        log "sorgenti HAOS gia' presenti (${cur}): ripristino i file tracciati"
        git -C "${OS_DIR}" reset -q --hard
    else
        log "clono HAOS ${HAOS_TAG} (con submodule buildroot)"
        git clone --depth 1 --branch "${HAOS_TAG}" --recurse-submodules --shallow-submodules \
            "${HAOS_REPO}" "${OS_DIR}"
    fi

    apply_overlay
    log "HAOS $(git -C "${OS_DIR}" describe --tags) pronto in ${OS_DIR}"
}
