#!/usr/bin/env bash
# Home Assistant OS nativo per Orange Pi 4 Pro (Allwinner A733) - punto d'ingresso unico.
# Gira sul PC di build (Ubuntu x86_64). Sull'Orange Pi non viene installato nulla.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for m in common deps fetch bootloader build verify; do
    # shellcheck disable=SC1090
    . "${HERE}/lib/${m}.sh"
done

usage() {
    cat <<USAGE
Uso: ./build.sh <comando> [opzioni]

  deps                       installa le dipendenze sul PC di build (apt, docker)
  fetch                      clona HAOS (tag ${HAOS_TAG}) e applica l'overlay Orange Pi 4 Pro
  bootloader [--from-image IMG] [--force]
                             produce boot0 + boot_package (da sorgenti, oppure da una
                             immagine funzionante gia' esistente)
  build [--skip-image-build] compila l'immagine (container docker, 1-4 ore)
  verify                     controlla config kernel e immagine
  shell                      shell nel container di build (debug)
  clean                      rimuove l'output di Buildroot (la cache resta)
  all                        deps, fetch, bootloader, build, verify

Variabili: HAOS_TAG (default ${HAOS_TAG}, oppure "latest"), WORK_DIR (default ./work)
USAGE
}

main() {
    local cmd="${1:-}"
    [ $# -gt 0 ] && shift
    case "${cmd}" in
        deps)       cmd_deps "$@" ;;
        fetch)      cmd_fetch "$@" ;;
        bootloader) cmd_bootloader "$@" ;;
        build)      cmd_build "$@" ;;
        verify)     cmd_verify "$@" ;;
        shell)      cmd_shell "$@" ;;
        clean)      cmd_clean "$@" ;;
        all)        cmd_deps; cmd_fetch; cmd_bootloader; cmd_build; cmd_verify ;;
        ""|-h|--help|help) usage ;;
        *) usage >&2; die "comando sconosciuto: ${cmd}" ;;
    esac
}

main "$@"
