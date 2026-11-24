#!/usr/bin/env bash
# Scrive l'immagine HAOS sulla microSD. Uso: ./flash.sh <immagine.img[.xz]> </dev/sdX>
# Nessuna opzione "--yes": devi riscrivere il nome del device per confermare.
set -Eeuo pipefail

die() { echo "ERRORE: $*" >&2; exit 1; }
[ $# -eq 2 ] || die "uso: $0 <immagine.img[.xz]> </dev/sdX>"
IMG="$1"; DEV="$2"

[ -f "${IMG}" ] || die "immagine non trovata: ${IMG}"
[ -b "${DEV}" ] || die "${DEV} non e' un block device"
case "${DEV}" in *[0-9]) [[ "${DEV}" =~ ^/dev/(nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$ ]] || die "${DEV} sembra una partizione: usa il disco intero (es. /dev/sdb)";; esac

TYPE="$(lsblk -dno TYPE "${DEV}")"; [ "${TYPE}" = "disk" ] || die "${DEV} non e' un disco intero (tipo ${TYPE})"
SIZE_B="$(blockdev --getsize64 "${DEV}")"
[ "${SIZE_B}" -ge $((8 * 1024 * 1024 * 1024)) ] || die "${DEV} e' piu' piccolo di 8 GB"
if [ "${SIZE_B}" -gt $((512 * 1024 * 1024 * 1024)) ]; then die "${DEV} supera 512 GB: non sembra una microSD, rifiuto"; fi

# rifiuta il disco di sistema
ROOT_SRC="$(findmnt -no SOURCE / || true)"
ROOT_DISK="$(lsblk -no PKNAME "${ROOT_SRC}" 2>/dev/null | head -1 || true)"
[ "/dev/${ROOT_DISK:-none}" != "${DEV}" ] || die "${DEV} e' il disco del sistema in uso"

if lsblk -nro MOUNTPOINT "${DEV}" | grep -q .; then die "${DEV} ha partizioni montate: smontale prima (umount)"; fi

echo "Device : ${DEV}"
lsblk -o NAME,SIZE,MODEL,TRAN,RM "${DEV}"
echo "Immagine: ${IMG}"
echo
echo "TUTTI i dati su ${DEV} verranno cancellati."
read -r -p "Per confermare riscrivi esattamente il device (${DEV}): " ANS
[ "${ANS}" = "${DEV}" ] || die "conferma non corrisponde, annullato"

SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
case "${IMG}" in
    *.xz) xz -dc "${IMG}" | ${SUDO} dd of="${DEV}" bs=4M conv=fsync status=progress ;;
    *)    ${SUDO} dd if="${IMG}" of="${DEV}" bs=4M conv=fsync status=progress ;;
esac
${SUDO} sync
${SUDO} partprobe "${DEV}" 2>/dev/null || true

echo
echo "Fatto. Inserisci la SD nella Orange Pi 4 Pro, collega la seriale (vedi SERIAL.md) e l'Ethernet, poi alimenta."
echo "Il primo avvio espande la partizione dati su tutta la SD e scarica Supervisor/Core: servono 10-20 minuti."
