#!/usr/bin/env bash
# build.sh deps - installa le dipendenze sul PC di build 

cmd_deps() {
    check_x86_64
    [ -r /etc/os-release ] && . /etc/os-release
    case "${ID:-}${ID_LIKE:-}" in
        *ubuntu*|*debian*) ;;
        *) die "distribuzione non supportata dallo script (serve Ubuntu/Debian): installa a mano i pacchetti elencati in lib/deps.sh" ;;
    esac

    local SUDO=""
    if [ "$(id -u)" -ne 0 ]; then need_cmd sudo; SUDO="sudo"; fi


    local pkgs=(
        git curl ca-certificates rsync xz-utils python3 xxd mtools dosfstools fdisk util-linux
        build-essential bison flex libssl-dev bc device-tree-compiler libncurses-dev
        gcc-arm-linux-gnueabi
        docker.io
    )
    log "installo pacchetti: ${pkgs[*]}"
    ${SUDO} apt-get update
    ${SUDO} apt-get install -y --no-install-recommends "${pkgs[@]}"

    if ! id -nG "${USER:-$(id -un)}" | tr ' ' '\n' | grep -qx docker; then
        log "aggiungo ${USER:-$(id -un)} al gruppo docker (serve un nuovo login)"
        ${SUDO} usermod -aG docker "${USER:-$(id -un)}" || warn "usermod fallito: usa sudo per docker"
    fi
    ${SUDO} systemctl enable --now docker >/dev/null 2>&1 || true

    mkdir -p "${WORK}"
    local free_gb
    free_gb="$(df -BG --output=avail "${WORK}" | tail -1 | tr -dc '0-9')"
    log "spazio libero in ${WORK}: ${free_gb} GB"
    [ "${free_gb}" -ge 80 ] || warn "consigliati almeno 80 GB liberi per cache e output di Buildroot"

    local mem_gb
    mem_gb="$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)"
    [ "${mem_gb}" -ge 8 ] || warn "RAM ${mem_gb} GB: sotto 8 GB la compilazione (LTO) puo' fallire per memoria"

    log "dipendenze installate. Se hai appena cambiato gruppo, esci e rientra, poi: ./build.sh all"
}
