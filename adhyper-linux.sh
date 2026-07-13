#!/usr/bin/env bash
# ============================================================================
#  AD HyperOptimize — Linux Edition
#  Deep system update, cleanup & performance tuning for Arch, Debian/Ubuntu,
#  Fedora and openSUSE (inkl. Derivate via ID_LIKE).
#
#  15 Module:
#    Update (PM/AUR/Flatpak/Snap/fwupd) · Deep Cleanup · Mirror-Optimierung
#    sysctl-Tuning (VM/BBR/Latenz) · I/O-Scheduler · CPU-Governor · ZRAM
#    Service-Audit · SSD-TRIM · Gaming · DNS (DoT) · Btrfs-Wartung
#    Security-Quickcheck · Auto-Maintenance-Timer · Health-Report
#
#  Modi:  TUI-Menü  |  --all  |  --dry-run  |  --revert  |  --help
#  Alles was das Script anlegt trägt das Prefix "adhyper" und ist über
#  --revert vollständig rücknehmbar (Backups: /etc/adhyper-backup).
# ============================================================================

set -uo pipefail

SCRIPT_VERSION="1.1.0"
BACKUP_DIR="/etc/adhyper-backup"
STATE_FILE="${BACKUP_DIR}/state.list"
LOG_FILE="/var/log/adhyper-optimize.log"
INSTALL_PATH="/usr/local/bin/adhyper-linux"
DRY_RUN=0
ASSUME_YES=0

# ---------------------------------------------------------------- colors ---
if [[ -t 1 ]]; then
    C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_B=$'\e[38;5;39m'
    C_C=$'\e[36m'; C_M=$'\e[35m'; C_W=$'\e[97m'; C_D=$'\e[2m'; C_0=$'\e[0m'
    C_BOLD=$'\e[1m'; C_ACC=$'\e[38;5;45m'; C_HDR=$'\e[38;5;208m'
else
    C_R=""; C_G=""; C_Y=""; C_B=""; C_C=""; C_M=""; C_W=""; C_D=""; C_0=""
    C_BOLD=""; C_ACC=""; C_HDR=""
fi

log()   { echo "${C_D}[$(date +%H:%M:%S)]${C_0} $*" | tee -a "$LOG_FILE" >&2; }
info()  { echo "${C_C}::${C_0} $*" | tee -a "$LOG_FILE" >&2; }
ok()    { echo "${C_G} ✔${C_0} $*" | tee -a "$LOG_FILE" >&2; }
warn()  { echo "${C_Y} ⚠${C_0} $*" | tee -a "$LOG_FILE" >&2; }
err()   { echo "${C_R} ✘${C_0} $*" | tee -a "$LOG_FILE" >&2; }
hr()    { echo "${C_D}────────────────────────────────────────────────────────────────${C_0}"; }
section(){ echo; echo "${C_ACC}${C_BOLD}▸ $*${C_0}"; hr; }

# run: execute or echo (dry-run). Usage: run <cmd> [args...]
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${C_M}[dry-run]${C_0} $*"
        return 0
    fi
    log "\$ $*"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
}

# track_state <line> — dedupe entry into state file
track_state() {
    [[ $DRY_RUN -eq 1 ]] && return 0
    mkdir -p "$BACKUP_DIR"
    grep -qxF "$1" "$STATE_FILE" 2>/dev/null || echo "$1" >> "$STATE_FILE"
}

# backup_file <path> — Original einmalig sichern
backup_file() {
    local path="$1"
    [[ $DRY_RUN -eq 1 || ! -f "$path" ]] && return 0
    if ! grep -qxF "RESTORE:${path}" "$STATE_FILE" 2>/dev/null; then
        mkdir -p "${BACKUP_DIR}$(dirname "$path")"
        cp -a "$path" "${BACKUP_DIR}${path}"
        track_state "RESTORE:${path}"
    fi
}

# write_file <path> <content> — mit Backup + State-Tracking, dry-run aware
write_file() {
    local path="$1" content="$2"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${C_M}[dry-run]${C_0} write ${path}:"
        echo "$content" | sed 's/^/    /'
        return 0
    fi
    if [[ -f "$path" ]]; then
        backup_file "$path"
    else
        track_state "DELETE:${path}"
    fi
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    ok "geschrieben: $path"
}

ask() {  # ask "Frage" -> 0=yes 1=no
    [[ $ASSUME_YES -eq 1 ]] && return 0
    local a
    read -rp "${C_Y}?${C_0} $1 [j/N] " a
    [[ "$a" =~ ^([jJyY])$ ]]
}

# ask_safe: wie ask, aber bei --all IMMER Nein (für riskante Optionen)
ask_safe() {
    [[ $ASSUME_YES -eq 1 ]] && return 1
    ask "$1"
}

pause() { [[ $ASSUME_YES -eq 1 ]] || read -rp "${C_D}[Enter] zurück zum Menü...${C_0}"; }

# ------------------------------------------------------------ detection ---
PM=""       # pacman|apt|dnf|zypper
DISTRO=""
AUR_HELPER=""
IS_LAPTOP=0

detect_system() {
    [[ -r /etc/os-release ]] && . /etc/os-release
    local id_all="${ID:-} ${ID_LIKE:-}"
    case " $id_all " in
        *" arch "*|*" archlinux "*|*" cachyos "*|*" endeavouros "*|*" manjaro "*) PM=pacman ;;
        *" debian "*|*" ubuntu "*|*" linuxmint "*|*" pop "*)                      PM=apt ;;
        *" fedora "*|*" rhel "*|*" nobara "*)                                     PM=dnf ;;
        *" suse "*|*" opensuse "*|*" opensuse-tumbleweed "*)                      PM=zypper ;;
    esac
    if [[ -z "$PM" ]]; then
        for p in pacman apt dnf zypper; do command -v "$p" &>/dev/null && { PM=$p; break; }; done
    fi
    [[ -z "$PM" ]] && { err "Kein unterstützter Paketmanager gefunden."; exit 1; }
    DISTRO="${PRETTY_NAME:-unknown}"

    if [[ "$PM" == pacman ]]; then
        for h in paru yay; do command -v "$h" &>/dev/null && { AUR_HELPER=$h; break; }; done
    fi

    local chassis
    chassis="$(hostnamectl chassis 2>/dev/null || cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "")"
    case "$chassis" in laptop|convertible|tablet|9|10|14|31) IS_LAPTOP=1 ;; esac
}

pkg_install() {  # pkg_install pkg1 [pkg2...] — best effort
    case "$PM" in
        pacman) run pacman -S --needed --noconfirm "$@" ;;
        apt)    run apt-get install -y "$@" ;;
        dnf)    run dnf install -y "$@" ;;
        zypper) run zypper --non-interactive install "$@" ;;
    esac
}

# ============================================================================
#  MODUL 1: SYSTEM-UPDATE
# ============================================================================
mod_update() {
    section "System-Update"
    case "$PM" in
        pacman)
            run pacman -Syu --noconfirm
            if [[ -n "$AUR_HELPER" ]]; then
                info "AUR-Update via $AUR_HELPER (als ${SUDO_USER:-root})"
                if [[ -n "${SUDO_USER:-}" && $DRY_RUN -eq 0 ]]; then
                    sudo -u "$SUDO_USER" "$AUR_HELPER" -Syu --noconfirm 2>&1 | tee -a "$LOG_FILE"
                else
                    run "$AUR_HELPER" -Syu --noconfirm
                fi
            fi
            local pacnews
            pacnews=$(find /etc -name '*.pacnew' 2>/dev/null)
            [[ -n "$pacnews" ]] && warn ".pacnew-Dateien gefunden — manuell mergen:"$'\n'"$pacnews"
            ;;
        apt)
            run apt-get update
            run apt-get full-upgrade -y
            ;;
        dnf)
            run dnf upgrade --refresh -y
            ;;
        zypper)
            run zypper refresh
            if [[ "${ID:-}" == "opensuse-tumbleweed" ]]; then
                run zypper --non-interactive dup
            else
                run zypper --non-interactive update
            fi
            ;;
    esac

    if command -v flatpak &>/dev/null; then
        info "Flatpak-Update"
        run flatpak update -y
    fi
    if command -v snap &>/dev/null; then
        info "Snap-Update"
        run snap refresh
    fi
    if command -v fwupdmgr &>/dev/null; then
        info "Firmware-Update (fwupd)"
        run fwupdmgr refresh --force
        run fwupdmgr update -y || true
    else
        warn "fwupd nicht installiert — Firmware-Updates übersprungen (Install: fwupd)"
    fi

    if [[ -f /var/run/reboot-required ]] || { [[ "$PM" == pacman ]] && [[ -e /usr/lib/modules ]] && ! ls "/usr/lib/modules/$(uname -r)" &>/dev/null; }; then
        warn "Reboot erforderlich (Kernel/Core-Update)."
    fi
    ok "Update abgeschlossen."
}

# ============================================================================
#  MODUL 2: DEEP CLEANUP
# ============================================================================
mod_cleanup() {
    section "Deep Cleanup"
    local before after
    before=$(df --output=avail -B1 / | tail -1)

    case "$PM" in
        pacman)
            local orphans
            orphans=$(pacman -Qtdq 2>/dev/null || true)
            if [[ -n "$orphans" ]]; then
                info "Orphans: $(echo "$orphans" | wc -l) Pakete"
                # shellcheck disable=SC2086
                run pacman -Rns --noconfirm $orphans
            else
                ok "Keine Orphan-Pakete."
            fi
            if command -v paccache &>/dev/null; then
                run paccache -rk2          # 2 Versionen behalten
                run paccache -ruk0         # deinstallierte komplett raus
            else
                warn "paccache fehlt (pacman-contrib) — Cache-Trim übersprungen"
            fi
            [[ -n "$AUR_HELPER" && -n "${SUDO_USER:-}" && $DRY_RUN -eq 0 ]] && \
                sudo -u "$SUDO_USER" "$AUR_HELPER" -Sc --noconfirm 2>&1 | tee -a "$LOG_FILE" || true
            ;;
        apt)
            run apt-get autoremove --purge -y
            run apt-get autoclean -y
            run apt-get clean
            local rc
            rc=$(dpkg -l 2>/dev/null | awk '/^rc/{print $2}')
            # shellcheck disable=SC2086
            [[ -n "$rc" ]] && run dpkg --purge $rc
            ;;
        dnf)
            run dnf autoremove -y
            run dnf clean all
            run dnf remove -y --oldinstallonly --setopt=installonly_limit=2 kernel 2>/dev/null || true
            ;;
        zypper)
            run zypper --non-interactive clean --all
            command -v purge-kernels &>/dev/null && run purge-kernels
            ;;
    esac

    if command -v flatpak &>/dev/null; then
        run flatpak uninstall --unused -y
        run rm -rf /var/tmp/flatpak-cache-*
    fi
    if command -v snap &>/dev/null; then
        info "Alte Snap-Revisionen entfernen"
        if [[ $DRY_RUN -eq 0 ]]; then
            snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | \
            while read -r name rev; do
                snap remove "$name" --revision="$rev" 2>&1 | tee -a "$LOG_FILE"
            done
            snap set system refresh.retain=2 2>/dev/null || true
        else
            echo "${C_M}[dry-run]${C_0} snap: disabled revisions entfernen, retain=2"
        fi
    fi

    info "Journal auf 100 MB / 2 Wochen begrenzen"
    run journalctl --vacuum-size=100M
    run journalctl --vacuum-time=2weeks

    info "Coredumps & Crash-Reports"
    run rm -rf /var/lib/systemd/coredump/*
    [[ -d /var/crash ]] && run rm -rf /var/crash/*

    info "Temp-Verzeichnisse (Dateien älter als 7 Tage)"
    run find /tmp -mindepth 1 -mtime +7 -delete
    run find /var/tmp -mindepth 1 -mtime +7 -delete

    if [[ -n "${SUDO_USER:-}" ]]; then
        local uhome
        uhome=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        if [[ -d "$uhome" ]]; then
            info "User-Cache ($SUDO_USER): Thumbnails + Trash>30d"
            run rm -rf "$uhome/.cache/thumbnails"
            [[ -d "$uhome/.local/share/Trash/files" ]] && \
                run find "$uhome/.local/share/Trash/files" -mindepth 1 -mtime +30 -exec rm -rf {} +
        fi
    fi

    after=$(df --output=avail -B1 / | tail -1)
    local freed=$(( (after - before) / 1024 / 1024 ))
    (( freed < 0 )) && freed=0
    ok "Cleanup fertig — ~${freed} MB freigegeben."
}

# ============================================================================
#  MODUL 3: MIRROR- & PAKETMANAGER-OPTIMIERUNG
# ============================================================================
mod_mirrors() {
    section "Mirror- & Paketmanager-Optimierung"
    case "$PM" in
        pacman)
            # pacman.conf: ParallelDownloads + Color
            if grep -qE '^#?ParallelDownloads' /etc/pacman.conf 2>/dev/null; then
                backup_file /etc/pacman.conf
                if [[ $DRY_RUN -eq 0 ]]; then
                    sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
                    sed -i 's/^#Color$/Color/' /etc/pacman.conf
                fi
                ok "pacman: ParallelDownloads=10, Color aktiviert."
            fi
            if ! command -v reflector &>/dev/null; then
                ask "reflector installieren (schnellste Mirrors automatisch)?" && pkg_install reflector
            fi
            if command -v reflector &>/dev/null; then
                backup_file /etc/pacman.d/mirrorlist
                info "Mirrors ranken (HTTPS, letzte 12h, nach Rate)..."
                run reflector --age 12 --protocol https --sort rate --latest 20 --save /etc/pacman.d/mirrorlist
                ok "Mirrorlist aktualisiert."
            fi
            ;;
        apt)
            info "apt nutzt bereits die Distro-Mirror-Auswahl."
            info "Tipp: In den 'Anwendungspaketquellen' den Server auf 'Beste Server' stellen (Mint/Ubuntu-GUI)."
            ;;
        dnf)
            backup_file /etc/dnf/dnf.conf
            if [[ $DRY_RUN -eq 0 ]]; then
                grep -q '^max_parallel_downloads' /etc/dnf/dnf.conf || echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
                grep -q '^fastestmirror' /etc/dnf/dnf.conf || echo "fastestmirror=True" >> /etc/dnf/dnf.conf
                grep -q '^defaultyes' /etc/dnf/dnf.conf || echo "defaultyes=True" >> /etc/dnf/dnf.conf
            else
                echo "${C_M}[dry-run]${C_0} dnf.conf: max_parallel_downloads=10, fastestmirror=True"
            fi
            ok "dnf: parallele Downloads + fastestmirror aktiv."
            ;;
        zypper)
            info "zypper: Mirror-Auswahl läuft über MirrorCache/CDN — nichts zu tun."
            ;;
    esac
}

# ============================================================================
#  MODUL 4: KERNEL / SYSCTL TUNING
# ============================================================================
mod_sysctl() {
    section "Kernel-/sysctl-Tuning"

    local ram_kb ram_gb swappiness pagecluster
    ram_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    ram_gb=$(( ram_kb / 1024 / 1024 ))

    if [[ -e /dev/zram0 ]] || [[ -f /etc/systemd/zram-generator.conf ]]; then
        swappiness=100; pagecluster=0
        info "ZRAM erkannt → swappiness=100, page-cluster=0"
    else
        swappiness=10; pagecluster=3
        info "Kein ZRAM → swappiness=10"
    fi

    local qdisc="fq_codel" cc=""
    if modprobe tcp_bbr 2>/dev/null || grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        cc="net.ipv4.tcp_congestion_control = bbr"
        qdisc="fq"
        ok "BBR verfügbar → aktiviere BBR + fq"
    else
        warn "BBR nicht verfügbar → fq_codel bleibt"
    fi

    local splitlock=""
    [[ -e /proc/sys/kernel/split_lock_mitigate ]] && splitlock="kernel.split_lock_mitigate = 0"

    write_file /etc/sysctl.d/99-adhyper-tuning.conf "\
# AD HyperOptimize — Kernel-Tuning (RAM: ${ram_gb} GB)
# Revert: adhyper-linux.sh --revert

## --- Virtual Memory ---
vm.swappiness = ${swappiness}
vm.page-cluster = ${pagecluster}
# Dentry/Inode-Cache länger behalten (Desktop-Responsiveness)
vm.vfs_cache_pressure = 50
# Absolute dirty-Limits statt Prozent -> keine Multi-GB-Writeback-Stalls
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 134217728
vm.dirty_writeback_centisecs = 1500
# Memory-Maps für Spiele/Wine/ASAN
vm.max_map_count = 2147483642
# Weniger proaktive Kompaktierung = weniger Latenz-Spikes
vm.compaction_proactiveness = 0
vm.watermark_boost_factor = 1
vm.watermark_scale_factor = 125

## --- Scheduler / Latenz ---
kernel.nmi_watchdog = 0
kernel.sched_autogroup_enabled = 1
${splitlock}

## --- Filesystem ---
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1024
fs.file-max = 2097152

## --- Netzwerk ---
net.core.default_qdisc = ${qdisc}
${cc}
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 1048576 16777216
net.core.netdev_max_backlog = 4096
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_max_syn_backlog = 8192"

    [[ -n "$cc" ]] && write_file /etc/modules-load.d/adhyper-bbr.conf "tcp_bbr"

    run sysctl --system
    ok "sysctl-Tuning aktiv."
}

# ============================================================================
#  MODUL 5: I/O-SCHEDULER
# ============================================================================
mod_iosched() {
    section "I/O-Scheduler (udev)"
    info "Geräte:"
    lsblk -dno NAME,ROTA,TYPE 2>/dev/null | awk '$3=="disk"{print "   " $1 " -> " ($2==1 ? "HDD" : "SSD/NVMe")}'

    write_file /etc/udev/rules.d/60-adhyper-iosched.rules "\
# AD HyperOptimize — I/O-Scheduler pro Gerätetyp
# NVMe: 'none' — Hardware-Queues, Scheduler-Overhead unnötig
ACTION==\"add|change\", KERNEL==\"nvme[0-9]*n[0-9]*\", ATTR{queue/scheduler}=\"none\"
# SATA/USB-SSD: mq-deadline — niedrige Latenz
ACTION==\"add|change\", KERNEL==\"sd[a-z]*|mmcblk[0-9]*\", ATTR{queue/rotational}==\"0\", ATTR{queue/scheduler}=\"mq-deadline\"
# HDD: bfq — Fairness bei Rotationsmedien
ACTION==\"add|change\", KERNEL==\"sd[a-z]*\", ATTR{queue/rotational}==\"1\", ATTR{queue/scheduler}=\"bfq\"
# Read-ahead für HDDs erhöhen
ACTION==\"add|change\", KERNEL==\"sd[a-z]*\", ATTR{queue/rotational}==\"1\", ATTR{bdi/read_ahead_kb}=\"2048\""

    if [[ $DRY_RUN -eq 0 ]]; then
        udevadm control --reload-rules
        udevadm trigger --subsystem-match=block
    fi
    ok "I/O-Scheduler-Regeln aktiv."
}

# ============================================================================
#  MODUL 6: CPU-GOVERNOR
# ============================================================================
mod_cpugov() {
    section "CPU-Governor"
    local gov_path=/sys/devices/system/cpu/cpu0/cpufreq
    if [[ ! -d $gov_path ]]; then
        warn "Kein cpufreq-Interface (VM/Container?) — übersprungen."
        return
    fi
    local driver current available target
    driver=$(cat "$gov_path/scaling_driver" 2>/dev/null || echo "?")
    current=$(cat "$gov_path/scaling_governor" 2>/dev/null || echo "?")
    available=$(cat "$gov_path/scaling_available_governors" 2>/dev/null || echo "?")
    info "Driver: $driver | aktuell: $current | verfügbar: $available"

    if [[ $IS_LAPTOP -eq 1 ]]; then
        warn "Laptop erkannt — 'performance' dauerhaft kostet Akku."
        if ask_safe "Trotzdem 'performance' setzen? (Nein = Governor belassen)"; then
            target="performance"
        else
            info "Governor unverändert."; return
        fi
    else
        target="performance"
        if ! ask "Governor 'performance' dauerhaft setzen? (empfohlen für Desktop/Gaming-Rig)"; then
            info "Governor unverändert."; return
        fi
    fi
    if ! grep -qw "$target" "$gov_path/scaling_available_governors" 2>/dev/null; then
        warn "'$target' nicht verfügbar bei Driver $driver — übersprungen."
        return
    fi

    write_file /etc/systemd/system/adhyper-cpugov.service "\
[Unit]
Description=AD HyperOptimize — CPU Governor (${target})
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo ${target} > \$g; done; for e in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do [ -w \$e ] && echo performance > \$e || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target"

    run systemctl daemon-reload
    run systemctl enable --now adhyper-cpugov.service
    ok "Governor '$target' gesetzt (persistiert via systemd-Service)."
}

# ============================================================================
#  MODUL 7: ZRAM
# ============================================================================
mod_zram() {
    section "ZRAM (komprimierter Swap im RAM)"
    if [[ -e /dev/zram0 ]] && ! [[ -f /etc/systemd/zram-generator.conf ]]; then
        warn "zram0 existiert bereits (fremdes Setup: zramswap/zram-config?) — übersprungen um Konflikte zu vermeiden."
        return
    fi

    if ! [[ -f /usr/lib/systemd/system-generators/zram-generator ]]; then
        info "Installiere zram-generator"
        case "$PM" in
            pacman) pkg_install zram-generator ;;
            apt)    pkg_install systemd-zram-generator || pkg_install zram-tools ;;
            dnf)    pkg_install zram-generator ;;
            zypper) pkg_install zram-generator ;;
        esac
    fi

    if [[ -f /usr/lib/systemd/system-generators/zram-generator ]] || [[ $DRY_RUN -eq 1 ]]; then
        write_file /etc/systemd/zram-generator.conf "\
# AD HyperOptimize — ZRAM
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap"
        run systemctl daemon-reload
        run systemctl restart systemd-zram-setup@zram0.service
        ok "ZRAM aktiv: $(swapon --show=NAME,SIZE,PRIO --noheadings 2>/dev/null | grep zram || echo 'nach Reboot aktiv')"
        info "Hinweis: sysctl-Modul danach (erneut) ausführen → swappiness wird auf 100 angepasst."
    elif command -v zramswap &>/dev/null; then
        write_file /etc/default/zramswap "\
# AD HyperOptimize — ZRAM (zram-tools)
ALGO=zstd
PERCENT=50
PRIORITY=100"
        run systemctl enable --now zramswap.service
        ok "ZRAM via zram-tools aktiv."
    else
        err "Kein zram-generator/zram-tools installierbar — übersprungen."
    fi
}

# ============================================================================
#  MODUL 8: SERVICE-AUDIT
# ============================================================================
mod_services() {
    section "Service-Audit"
    info "Boot-Zeit:"
    systemd-analyze 2>/dev/null | tee -a "$LOG_FILE" || true
    info "Top 10 langsamste Boot-Services:"
    systemd-analyze blame 2>/dev/null | head -10 | tee -a "$LOG_FILE" || true
    echo

    # SAFE = darf bei --all automatisch deaktiviert werden
    local candidates=(
        "SAFE|NetworkManager-wait-online.service|Wartet beim Boot auf Netzwerk (~5-15s Bootzeit)"
        "SAFE|systemd-networkd-wait-online.service|Wartet beim Boot auf Netzwerk"
        "ASK|ModemManager.service|Mobilfunk-Modems — ohne WWAN-Karte unnötig"
        "ASK|avahi-daemon.service|mDNS/Zeroconf — nur für lokale Discovery (Drucker/Chromecast) nötig"
        "ASK|cups.service|Druckdienst — wird bei Bedarf socket-aktiviert (cups.socket bleibt an)"
        "ASK|bluetooth.service|Bluetooth — nur deaktivieren wenn ungenutzt"
        "ASK|packagekit.service|GUI-Paket-Backend — bei CLI-only-Nutzung unnötig"
    )
    local touched=0
    for entry in "${candidates[@]}"; do
        local mode="${entry%%|*}" rest="${entry#*|}"
        local svc="${rest%%|*}" desc="${rest#*|}"
        if systemctl is-enabled "$svc" &>/dev/null; then
            echo "  ${C_W}${svc}${C_0}"
            echo "    ${C_D}${desc}${C_0}"
            local doit=1
            if [[ "$mode" == "SAFE" ]]; then
                ask "  → deaktivieren?" && doit=0
            else
                ask_safe "  → deaktivieren?" && doit=0
            fi
            if [[ $doit -eq 0 ]]; then
                run systemctl disable --now "$svc"
                track_state "REENABLE:${svc}"
                touched=1
            fi
        fi
    done
    [[ $touched -eq 0 ]] && ok "Keine Änderungen an Services."

    info "Fehlgeschlagene Units:"
    systemctl --failed --no-legend --no-pager 2>/dev/null | tee -a "$LOG_FILE" || true
}

# ============================================================================
#  MODUL 9: SSD-TRIM
# ============================================================================
mod_trim() {
    section "SSD-TRIM"
    if lsblk -dno ROTA 2>/dev/null | grep -qw 0; then
        run systemctl enable --now fstrim.timer
        ok "fstrim.timer aktiv (wöchentlich)."
        [[ $DRY_RUN -eq 0 ]] && info "Einmaliger Trim jetzt:" && run fstrim -av
    else
        warn "Keine SSD erkannt — übersprungen."
    fi
}

# ============================================================================
#  MODUL 10: GAMING-TWEAKS
# ============================================================================
mod_gaming() {
    section "Gaming-Tweaks"

    if ! command -v gamemoderun &>/dev/null; then
        if ask "Feral GameMode installieren? (CPU-Governor/Prio automatisch beim Spielen)"; then
            case "$PM" in
                pacman) pkg_install gamemode lib32-gamemode || pkg_install gamemode ;;
                *)      pkg_install gamemode ;;
            esac
            info "Nutzung: gamemoderun %command%  (Steam-Startoption)"
        fi
    else
        ok "GameMode bereits installiert."
    fi

    write_file /etc/security/limits.d/99-adhyper-esync.conf "\
# AD HyperOptimize — hohe nofile-Limits für Wine/Proton esync
* hard nofile 1048576
* soft nofile 1048576"
    ok "esync-Limits gesetzt (wirksam nach Re-Login)."

    if [[ ! -f /etc/sysctl.d/99-adhyper-tuning.conf ]]; then
        warn "sysctl-Modul noch nicht gelaufen — max_map_count/split_lock-Tweaks fehlen noch."
    fi

    echo
    warn "Optional: CPU-Mitigations abschalten (bis ~5-10% Perf, ABER: Spectre/Meltdown-Schutz weg)."
    warn "Nur auf reinen Gaming-Maschinen ohne sensible Daten sinnvoll."
    if ask_safe "Kernel-Parameter 'mitigations=off' setzen?"; then
        if [[ -f /etc/default/grub ]]; then
            if ! grep -q "mitigations=off" /etc/default/grub; then
                backup_file /etc/default/grub
                [[ $DRY_RUN -eq 0 ]] && sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 mitigations=off"/' /etc/default/grub
                if command -v update-grub &>/dev/null; then run update-grub
                elif command -v grub2-mkconfig &>/dev/null; then run grub2-mkconfig -o /boot/grub2/grub.cfg
                elif command -v grub-mkconfig &>/dev/null; then run grub-mkconfig -o /boot/grub/grub.cfg
                fi
                ok "mitigations=off gesetzt — aktiv nach Reboot."
            else
                ok "mitigations=off bereits gesetzt."
            fi
        elif [[ -d /boot/loader/entries ]]; then
            warn "systemd-boot erkannt — 'mitigations=off' manuell in /boot/loader/entries/*.conf an 'options' anhängen."
        else
            warn "Bootloader nicht erkannt — Parameter manuell setzen."
        fi
    fi

    echo
    if lspci 2>/dev/null | grep -qi nvidia; then
        info "NVIDIA erkannt:"
        echo "   • Treiber aktuell? → nvidia-smi"
        echo "   • Shader-Cache behalten: __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1"
        echo "   • Bei Stottern: nvidia-drm.modeset=1 als Kernel-Param prüfen"
    fi
    if lspci 2>/dev/null | grep -iE "vga|3d" | grep -qiE "amd|ati|radeon"; then
        info "AMD-GPU erkannt — Mesa aktuell halten; RADV ist Default-Vulkan-Treiber."
    fi
    ok "Gaming-Tweaks fertig."
}

# ============================================================================
#  MODUL 11: DNS (schnell + verschlüsselt)
# ============================================================================
mod_dns() {
    section "DNS-Optimierung (Cloudflare/Quad9 + DNS-over-TLS)"
    if ! systemctl is-active systemd-resolved &>/dev/null; then
        warn "systemd-resolved läuft nicht — DNS-Modul übersprungen."
        info "Alternative: DNS im NetworkManager/Router auf 1.1.1.1 / 9.9.9.9 stellen."
        return
    fi
    info "Setzt: Cloudflare (1.1.1.1) primär, Quad9 (9.9.9.9) Fallback, DoT opportunistic."
    if ! ask_safe "DNS-Server systemweit ändern?"; then
        info "Übersprungen."; return
    fi

    write_file /etc/systemd/resolved.conf.d/99-adhyper-dns.conf "\
# AD HyperOptimize — DNS
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com
FallbackDNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
Cache=yes"

    run systemctl restart systemd-resolved
    if [[ $DRY_RUN -eq 0 ]]; then
        sleep 1
        resolvectl status 2>/dev/null | grep -E "DNS Server|Current DNS" | head -4 || true
    fi
    ok "DNS umgestellt (revertierbar)."
}

# ============================================================================
#  MODUL 12: BTRFS-WARTUNG
# ============================================================================
mod_btrfs() {
    section "Btrfs-Wartung"
    local fstype
    fstype=$(findmnt -no FSTYPE / 2>/dev/null || echo "")
    if [[ "$fstype" != "btrfs" ]]; then
        info "Root-FS ist ${fstype:-unbekannt}, kein Btrfs — übersprungen."
        return
    fi

    info "Btrfs-Root erkannt. Belegung:"
    btrfs filesystem usage / 2>/dev/null | head -8 || true
    echo

    if ask "Balance ausführen? (defragmentiert Chunk-Allokation, dauert wenige Minuten)"; then
        run btrfs balance start -dusage=50 -musage=50 /
        ok "Balance fertig."
    fi
    if ask "Scrub starten? (prüft Checksummen, läuft im Hintergrund)"; then
        run btrfs scrub start /
        info "Status: btrfs scrub status /"
    fi
    if ! grep -q "compress" /etc/fstab 2>/dev/null; then
        info "Tipp: 'compress=zstd:1' als Mount-Option in /etc/fstab spart Platz + oft schneller."
    fi
    if ! systemctl is-enabled btrfs-scrub@-.timer &>/dev/null 2>&1; then
        ask "Monatlichen Scrub-Timer aktivieren?" && run systemctl enable --now btrfs-scrub@-.timer || true
    fi
}

# ============================================================================
#  MODUL 13: SECURITY-QUICKCHECK  (read-only)
# ============================================================================
mod_security() {
    section "Security-Quickcheck (nur Analyse, ändert nichts)"

    echo "${C_W}— Firewall —${C_0}"
    if command -v ufw &>/dev/null; then
        ufw status 2>/dev/null | head -3
    elif command -v firewall-cmd &>/dev/null; then
        echo "firewalld: $(firewall-cmd --state 2>/dev/null || echo 'inaktiv')"
    elif command -v nft &>/dev/null && [[ -n "$(nft list ruleset 2>/dev/null)" ]]; then
        echo "nftables: Regeln aktiv"
    else
        warn "Keine aktive Firewall erkannt (ufw/firewalld/nftables)."
    fi

    echo; echo "${C_W}— SSH —${C_0}"
    if [[ -f /etc/ssh/sshd_config ]] && systemctl is-active sshd &>/dev/null || systemctl is-active ssh &>/dev/null; then
        local prl pwa
        prl=$(sshd -T 2>/dev/null | awk '/^permitrootlogin/{print $2}')
        pwa=$(sshd -T 2>/dev/null | awk '/^passwordauthentication/{print $2}')
        echo "   PermitRootLogin: ${prl:-?}   PasswordAuthentication: ${pwa:-?}"
        [[ "${prl:-no}" == "yes" ]] && warn "SSH-Root-Login erlaubt — 'PermitRootLogin no' empfohlen."
        [[ "${pwa:-no}" == "yes" ]] && info "Passwort-Auth aktiv — Keys sind sicherer."
    else
        echo "   Kein SSH-Server aktiv."
    fi

    echo; echo "${C_W}— Offene Ports (listening) —${C_0}"
    ss -tulnH 2>/dev/null | awk '{printf "   %-6s %s\n", $1, $5}' | sort -u | head -15

    echo; echo "${C_W}— Auto-Updates —${C_0}"
    case "$PM" in
        apt)
            if dpkg -l unattended-upgrades &>/dev/null 2>&1; then
                echo "   unattended-upgrades installiert."
            else
                info "Tipp: 'unattended-upgrades' für automatische Security-Patches."
            fi ;;
        dnf)
            systemctl is-enabled dnf-automatic.timer &>/dev/null && echo "   dnf-automatic aktiv." || \
                info "Tipp: dnf-automatic für automatische Security-Patches." ;;
        pacman)
            info "Rolling Release — regelmäßig 'pacman -Syu' (oder Modul 1) reicht." ;;
        zypper)
            info "Tipp: 'zypper patch' regelmäßig oder YaST Online-Update." ;;
    esac

    echo; echo "${C_W}— Letzte fehlgeschlagene Logins —${C_0}"
    lastb -n 5 2>/dev/null | head -5 || echo "   (keine Daten)"
    ok "Security-Check fertig."
}

# ============================================================================
#  MODUL 14: AUTO-MAINTENANCE (wöchentlicher Timer)
# ============================================================================
mod_automaint() {
    section "Auto-Maintenance-Timer"
    info "Installiert das Script nach ${INSTALL_PATH} und richtet einen"
    info "wöchentlichen systemd-Timer ein: Update-Check + Cleanup, vollautomatisch."
    if ! ask "Einrichten?"; then
        info "Übersprungen."; return
    fi

    if [[ $DRY_RUN -eq 0 ]]; then
        cp -f "$(readlink -f "$0")" "$INSTALL_PATH"
        chmod 755 "$INSTALL_PATH"
        track_state "DELETE:${INSTALL_PATH}"
    else
        echo "${C_M}[dry-run]${C_0} cp $0 $INSTALL_PATH"
    fi

    write_file /etc/systemd/system/adhyper-maintenance.service "\
[Unit]
Description=AD HyperOptimize — wöchentliche Wartung (Cleanup)
After=network-online.target

[Service]
Type=oneshot
ExecStart=${INSTALL_PATH} --clean
Nice=19
IOSchedulingClass=idle"

    write_file /etc/systemd/system/adhyper-maintenance.timer "\
[Unit]
Description=AD HyperOptimize — wöchentlicher Wartungs-Timer

[Timer]
OnCalendar=Sun 04:00
Persistent=true
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target"

    run systemctl daemon-reload
    run systemctl enable --now adhyper-maintenance.timer
    ok "Timer aktiv: sonntags 04:00 Uhr. Status: systemctl list-timers adhyper*"
}

# ============================================================================
#  MODUL 15: HEALTH-REPORT
# ============================================================================
mod_health() {
    section "System-Health-Report"

    echo "${C_W}Host:${C_0} $(hostnamectl hostname 2>/dev/null || hostname) | ${C_W}Kernel:${C_0} $(uname -r) | ${C_W}Distro:${C_0} $DISTRO"
    echo "${C_W}Uptime:${C_0}$(uptime -p 2>/dev/null | sed 's/up//')"
    echo

    echo "${C_W}— Speicher —${C_0}"
    free -h | tee -a "$LOG_FILE"
    echo
    echo "${C_W}— Disks —${C_0}"
    df -h -x tmpfs -x devtmpfs -x overlay 2>/dev/null | tee -a "$LOG_FILE"
    echo

    echo "${C_W}— Fehlgeschlagene Units —${C_0}"
    systemctl --failed --no-pager 2>/dev/null | tee -a "$LOG_FILE" || true
    echo
    echo "${C_W}— Journal-Errors (letzter Boot, max 15) —${C_0}"
    journalctl -p err -b --no-pager -n 15 2>/dev/null | tee -a "$LOG_FILE" || true
    echo

    if command -v smartctl &>/dev/null; then
        echo "${C_W}— SMART —${C_0}"
        for d in /dev/nvme[0-9]n1 /dev/sd[a-z]; do
            [[ -b "$d" ]] || continue
            local h
            h=$(smartctl -H "$d" 2>/dev/null | grep -iE "overall-health|SMART Health Status" | awk -F: '{print $2}' | xargs)
            echo "   $d: ${h:-unbekannt}"
        done
    else
        warn "smartmontools nicht installiert — SMART-Check übersprungen."
    fi

    if command -v sensors &>/dev/null; then
        echo; echo "${C_W}— Temperaturen —${C_0}"
        sensors 2>/dev/null | grep -E "°C" | head -12
    fi

    echo
    echo "${C_W}— Aktive Tweaks (adhyper) —${C_0}"
    ls -1 /etc/sysctl.d/99-adhyper* /etc/udev/rules.d/60-adhyper* \
          /etc/systemd/system/adhyper* /etc/systemd/zram-generator.conf \
          /etc/security/limits.d/99-adhyper* /etc/systemd/resolved.conf.d/99-adhyper* 2>/dev/null || echo "   keine"
    ok "Report fertig. Log: $LOG_FILE"
}

# ============================================================================
#  REVERT
# ============================================================================
mod_revert() {
    section "Revert aller AD-HyperOptimize-Tweaks"
    if [[ ! -f "$STATE_FILE" ]]; then
        warn "Kein State-File ($STATE_FILE) — nichts zu reverten."
        return
    fi
    ask "Wirklich alle Tweaks zurücknehmen?" || return

    # Timer/Services zuerst stoppen
    if [[ $DRY_RUN -eq 0 ]]; then
        systemctl disable --now adhyper-cpugov.service 2>/dev/null || true
        systemctl disable --now adhyper-maintenance.timer 2>/dev/null || true
    fi

    while IFS=: read -r action target; do
        case "$action" in
            DELETE)
                if [[ -e "$target" ]]; then
                    run rm -f "$target"
                    ok "entfernt: $target"
                fi
                ;;
            RESTORE)
                local bk="${BACKUP_DIR}${target}"
                if [[ -f "$bk" ]]; then
                    run cp -a "$bk" "$target"
                    ok "wiederhergestellt: $target"
                fi
                ;;
            REENABLE)
                run systemctl enable --now "$target"
                ok "reaktiviert: $target"
                ;;
        esac
    done < "$STATE_FILE"

    if [[ $DRY_RUN -eq 0 ]]; then
        systemctl daemon-reload
        sysctl --system >/dev/null 2>&1 || true
        udevadm control --reload-rules 2>/dev/null || true
        systemctl restart systemd-resolved 2>/dev/null || true
        rm -rf "$BACKUP_DIR"
    fi
    warn "Falls mitigations=off gesetzt war → GRUB-Config wurde restauriert, update-grub/grub-mkconfig läuft ggf. beim nächsten Kernel-Update. Reboot empfohlen."
    ok "Revert abgeschlossen."
}

# ============================================================================
#  TUI
# ============================================================================
run_all() {
    local steps=(mod_update mod_cleanup mod_mirrors mod_zram mod_sysctl mod_iosched
                 mod_cpugov mod_trim mod_services mod_gaming mod_security mod_health)
    local i=0 total=${#steps[@]}
    for step in "${steps[@]}"; do
        i=$((i+1))
        echo; echo "${C_HDR}${C_BOLD}━━ Schritt ${i}/${total} ━━${C_0}"
        "$step"
    done
}

dashboard() {
    local mem_used mem_total disk_pct gov tweaks bbr zram
    mem_used=$(free -h | awk '/^Mem/{print $3}')
    mem_total=$(free -h | awk '/^Mem/{print $2}')
    disk_pct=$(df --output=pcent / | tail -1 | xargs)
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "n/a")
    tweaks=$(ls -1 /etc/sysctl.d/99-adhyper* /etc/udev/rules.d/60-adhyper* \
                   /etc/systemd/system/adhyper*.service /etc/systemd/system/adhyper*.timer \
                   /etc/security/limits.d/99-adhyper* /etc/systemd/resolved.conf.d/99-adhyper* 2>/dev/null | wc -l)
    [[ "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)" == "bbr" ]] && bbr="${C_G}✔${C_0}" || bbr="${C_D}—${C_0}"
    swapon --show=NAME --noheadings 2>/dev/null | grep -q zram && zram="${C_G}✔${C_0}" || zram="${C_D}—${C_0}"

    echo " ${C_D}┌${C_0} RAM ${C_W}${mem_used}${C_0}${C_D}/${mem_total}${C_0}  Disk/ ${C_W}${disk_pct}${C_0}  Gov ${C_W}${gov}${C_0}  BBR ${bbr}  ZRAM ${zram}  Tweaks ${C_W}${tweaks}${C_0} aktiv"
}

banner() {
    clear 2>/dev/null || true
    echo "${C_B}${C_BOLD}"
    cat <<'EOF'
    ___    ____     __  __                      ____        __  _           _
   /   |  / __ \   / / / /_  ______  ___  _____/ __ \____  / /_(_)___ ___  (_)___  ___
  / /| | / / / /  / /_/ / / / / __ \/ _ \/ ___/ / / / __ \/ __/ / __ `__ \/ /_  / / _ \
 / ___ |/ /_/ /  / __  / /_/ / /_/ /  __/ /  / /_/ / /_/ / /_/ / / / / / / / / /_/  __/
/_/  |_/_____/  /_/ /_/\__, / .___/\___/_/   \____/ .___/\__/_/_/ /_/ /_/_/ /___/\___/
                      /____/_/                   /_/
EOF
    echo "${C_0}${C_ACC}                                                          Linux Edition${C_0}"
    echo " ${C_D}v${SCRIPT_VERSION} · ${DISTRO} · ${PM}$([[ -n $AUR_HELPER ]] && echo "+${AUR_HELPER}") · $(uname -r)$([[ $DRY_RUN -eq 1 ]] && echo " · ${C_M}${C_BOLD}DRY-RUN${C_0}${C_D}")${C_0}"
    dashboard
    hr
}

menu_item() { printf "  ${C_W}%3s${C_0}) %-22s ${C_D}%s${C_0}\n" "$1" "$2" "$3"; }

menu() {
    while true; do
        banner
        echo " ${C_HDR}${C_BOLD}◆ UPDATE & WARTUNG${C_0}"
        menu_item 1  "System-Update"        "Pakete · AUR · Flatpak · Snap · Firmware"
        menu_item 2  "Deep Cleanup"         "Orphans · Caches · Logs · alte Kernel"
        menu_item 3  "Mirror-Optimierung"   "schnellste Mirrors · parallele Downloads"
        echo
        echo " ${C_HDR}${C_BOLD}◆ PERFORMANCE${C_0}"
        menu_item 4  "Kernel/sysctl"        "VM · Netzwerk/BBR · Latenz"
        menu_item 5  "I/O-Scheduler"        "NVMe→none · SSD→mq-deadline · HDD→bfq"
        menu_item 6  "CPU-Governor"         "performance, persistent"
        menu_item 7  "ZRAM"                 "zstd-Swap im RAM, bis 8 GB"
        menu_item 8  "Service-Audit"        "Boot-Analyse · unnötige Dienste"
        menu_item 9  "SSD-TRIM"             "fstrim.timer"
        menu_item 10 "Gaming-Tweaks"        "GameMode · esync · mitigations opt-in"
        echo
        echo " ${C_HDR}${C_BOLD}◆ EXTRAS${C_0}"
        menu_item 11 "DNS-Optimierung"      "Cloudflare/Quad9 · DNS-over-TLS"
        menu_item 12 "Btrfs-Wartung"        "Balance · Scrub · Compression-Check"
        menu_item 13 "Security-Check"       "Firewall · SSH · offene Ports (read-only)"
        menu_item 14 "Auto-Maintenance"     "wöchentlicher Cleanup-Timer"
        menu_item 15 "Health-Report"        "SMART · failed units · Temps"
        hr
        echo "   ${C_G}a${C_0}) ALLES ausführen      ${C_Y}r${C_0}) Revert      ${C_M}d${C_0}) Dry-Run $([[ $DRY_RUN -eq 1 ]] && echo "${C_M}[AN]${C_0}" || echo "${C_D}[aus]${C_0}")      ${C_R}q${C_0}) Ende"
        hr
        local choice
        read -rp "  ${C_ACC}❯${C_0} " choice
        case "$choice" in
            1)  mod_update;    pause ;;
            2)  mod_cleanup;   pause ;;
            3)  mod_mirrors;   pause ;;
            4)  mod_sysctl;    pause ;;
            5)  mod_iosched;   pause ;;
            6)  mod_cpugov;    pause ;;
            7)  mod_zram;      pause ;;
            8)  mod_services;  pause ;;
            9)  mod_trim;      pause ;;
            10) mod_gaming;    pause ;;
            11) mod_dns;       pause ;;
            12) mod_btrfs;     pause ;;
            13) mod_security;  pause ;;
            14) mod_automaint; pause ;;
            15) mod_health;    pause ;;
            a|A) run_all;      pause ;;
            r|R) mod_revert;   pause ;;
            d|D) DRY_RUN=$((1 - DRY_RUN)) ;;
            q|Q) exit 0 ;;
            *) ;;
        esac
    done
}

usage() {
    cat <<EOF
AD HyperOptimize — Linux Edition v${SCRIPT_VERSION}

Usage: sudo $0 [OPTION]
  (ohne Option)   interaktives Menü
  --all           alle Kern-Module non-interaktiv (riskante Optionen bleiben aus)
  --update        nur Update
  --clean         nur Cleanup
  --tune          zram + sysctl + iosched + trim
  --security      nur Security-Quickcheck
  --health        nur Health-Report
  --revert        alle Tweaks zurücknehmen
  --dry-run       nichts ausführen, nur anzeigen (kombinierbar)
  -h, --help      diese Hilfe
EOF
}

main() {
    local action="menu"
    for arg in "$@"; do
        case "$arg" in
            --dry-run)  DRY_RUN=1 ;;
            --all)      action="all"; ASSUME_YES=1 ;;
            --update)   action="update" ;;
            --clean)    action="clean"; ASSUME_YES=1 ;;
            --tune)     action="tune" ;;
            --security) action="security" ;;
            --health)   action="health" ;;
            --revert)   action="revert" ;;
            -h|--help)  usage; exit 0 ;;
            *) err "Unbekannte Option: $arg"; usage; exit 1 ;;
        esac
    done

    if [[ $EUID -eq 0 ]]; then
        touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/adhyper-optimize.log"
    else
        LOG_FILE="/tmp/adhyper-optimize.log"
        if [[ "$action" == "health" || "$action" == "security" || $DRY_RUN -eq 1 ]]; then
            warn "Ohne root — einige Checks eingeschränkt."
        else
            exec sudo -E "$0" "$@"
        fi
    fi
    log "=== AD HyperOptimize v${SCRIPT_VERSION} gestartet (action=$action, dry-run=$DRY_RUN) ==="

    detect_system
    case "$action" in
        menu)     menu ;;
        all)      banner; run_all ;;
        update)   banner; mod_update ;;
        clean)    mod_cleanup ;;
        tune)     banner; mod_zram; mod_sysctl; mod_iosched; mod_trim ;;
        security) banner; mod_security ;;
        health)   banner; mod_health ;;
        revert)   banner; mod_revert ;;
    esac
}

main "$@"
