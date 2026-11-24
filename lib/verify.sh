#!/usr/bin/env bash
# build.sh verify - controlla config kernel e immagine prodotta (senza bisogno della scheda).

# Simboli senza i quali HAOS non parte o Supervisor/Docker non funzionano.
VERIFY_CRITICAL_Y="EROFS_FS OVERLAY_FS EXT4_FS VFAT_FS SQUASHFS CGROUPS MEMCG NAMESPACES USER_NS NET_NS PID_NS IPC_NS UTS_NS NETFILTER SECCOMP SECURITY SECURITY_APPARMOR AW_MMC AW_UART_NG DEVTMPFS"
VERIFY_CRITICAL_YM="VETH BRIDGE NF_TABLES AW_STMMAC_ETH STMMAC_ETH"

_kernel_config_file() {
    local f
    f="$(find "${OS_DIR}/output/build" -maxdepth 2 -path "*/linux-*/.config" 2>/dev/null | head -1 || true)"
    [ -n "${f}" ] || die "config kernel finale non trovata in ${OS_DIR}/output/build/linux-*/.config: esegui prima ./build.sh build"
    echo "${f}"
}

_verify_kernel() {
    local cfg be
    cfg="$(_kernel_config_file)"
    be="${OS_DIR}/buildroot-external"
    log "config kernel: ${cfg}"
    python3 - "${cfg}" "${VERIFY_CRITICAL_Y}" "${VERIFY_CRITICAL_YM}" \
        "${be}/kernel/v6.18.y/haos.config" "${be}/kernel/v6.18.y/docker.config" \
        "${be}/kernel/v6.18.y/device-support.config" "${be}/board/xunlong/orangepi-4pro/kernel.config" <<'PY'
import re, sys
cfg, crit_y, crit_ym, frags = sys.argv[1], sys.argv[2].split(), sys.argv[3].split(), sys.argv[4:]
final = {}
for line in open(cfg, errors="replace"):
    m = re.match(r"CONFIG_(\w+)=(.*)", line.strip())
    if m: final[m.group(1)] = m.group(2).strip('"')
    m = re.match(r"# CONFIG_(\w+) is not set", line.strip())
    if m: final[m.group(1)] = "n"
bad = []
for s in crit_y:
    if final.get(s) != "y": bad.append((s, "y", final.get(s, "ASSENTE")))
for s in crit_ym:
    if final.get(s) not in ("y", "m"): bad.append((s, "y|m", final.get(s, "ASSENTE")))
missing = []
for fr in frags:
    for line in open(fr):
        line = line.strip()
        m = re.match(r"CONFIG_(\w+)=(\w+)$", line)
        want = None
        if m: want = (m.group(1), m.group(2))
        else:
            m = re.match(r"# CONFIG_(\w+) is not set", line)
            if m: want = (m.group(1), "n")
        if not want or want[0] in ("LOCALVERSION", "CMDLINE"): continue
        sym, val = want
        got = final.get(sym, "ASSENTE")
        ok = (got == val) or (val == "m" and got == "y") or (val == "n" and got in ("n", "ASSENTE"))
        if not ok: missing.append((sym, val, got, fr.split("/")[-1]))
print("Simboli critici KO: %d" % len(bad))
for s, w, g in bad: print("  CRITICO  CONFIG_%s: voluto %s, trovato %s" % (s, w, g))
print("Richieste dei frammenti HAOS non soddisfatte: %d (molte sono simboli che nel 6.6 vendor non esistono)" % len(missing))
for s, w, g, f in missing[:60]: print("  warn  %-34s voluto %-3s trovato %-8s (%s)" % ("CONFIG_" + s, w, g, f))
if len(missing) > 60: print("  ... altre %d" % (len(missing) - 60))
sys.exit(1 if bad else 0)
PY
}

_verify_image() {
    local img="" f tmp="" rc=0
    for f in "${WORK}"/images/haos_*.img.xz "${WORK}"/images/haos_*.img; do [ -e "${f}" ] && img="${f}"; done
    [ -n "${img}" ] || die "nessuna immagine in ${WORK}/images: esegui ./build.sh build"
    need_cmd python3 sfdisk mdir
    case "${img}" in
        *.xz) need_cmd xz; tmp="$(mktemp -p "${WORK}" verify.XXXXXX.img)"; log "decomprimo ${img}"; xz -dc "${img}" > "${tmp}"; img="${tmp}" ;;
    esac
    log "controllo immagine"
    python3 - "${img}" "${BOOT0_OFFSET_KIB}" "${BOOTPKG_OFFSET_KIB}" "${SPL_AREA_MIB}" <<'PY' || rc=$?
import json, re, subprocess, sys
img, b0, bp, area = sys.argv[1], int(sys.argv[2]) * 1024, int(sys.argv[3]) * 1024, int(sys.argv[4]) * 1024 * 1024
errs = []
def chk(cond, msg):
    print(("  ok     " if cond else "  ERRORE ") + msg)
    if not cond: errs.append(msg)
f = open(img, "rb")
mbr = f.read(512)
chk(mbr[510:512] == b"\x55\xaa", "firma MBR 55AA")
chk(mbr[0x1B8:0x1BC] == bytes.fromhex("73736148"), "disk signature 0x48617373 (PARTUUID=48617373-NN)")
f.seek(b0 + 4); chk(f.read(8) == b"eGON.BT0", "boot0 (eGON.BT0) a 8 KiB")
f.seek(bp); chk(any(f.read(4096)), "boot_package presente a 16400 KiB")
pt = json.loads(subprocess.check_output(["sfdisk", "-J", img]))["partitiontable"]
parts = {int(re.search(r"(\d+)$", p["node"]).group(1)): p for p in pt["partitions"]}
chk(pt["label"] == "dos", "tabella partizioni MBR (dos)")
chk(1 in parts and parts[1]["start"] * 512 >= area, "partizione 1 (boot) parte dopo i 32 MiB riservati (start %s)" % (parts.get(1, {}).get("start")))
for n in (5, 6, 7, 8, 9, 3, 4):
    chk(n in parts, "partizione %d presente" % n)
if 6 in parts:
    f.seek(parts[6]["start"] * 512 + 1024)
    chk(f.read(4) == bytes.fromhex("e2e1f5e0"), "partizione 6 (system0) e' erofs: root=PARTUUID=48617373-06")
if 1 in parts:
    out = subprocess.run(["mdir", "-b", "-i", "%s@@%d" % (img, parts[1]["start"] * 512), "::"], capture_output=True, text=True)
    names = {l.strip().split("/")[-1] for l in out.stdout.splitlines()}
    for n in ("Image", "sun60i-a733-orangepi-4-pro.dtb", "boot.scr", "cmdline.txt", "haos-config.txt"):
        chk(n in names, "boot FAT contiene %s" % n)
sys.exit(1 if errs else 0)
PY
    [ -z "${tmp}" ] || rm -f "${tmp}"
    return "${rc}"
}

cmd_verify() {
    local rc=0
    _verify_kernel || rc=1
    _verify_image || rc=1
    if [ "${rc}" -ne 0 ]; then die "verifica fallita: correggi prima di flashare"; fi
    log "verifica superata"
}
