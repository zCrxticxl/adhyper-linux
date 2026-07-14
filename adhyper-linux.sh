#!/usr/bin/env bash
# ============================================================================
#  AD HyperOptimize — Linux Edition
#  Deep system update, cleanup & performance tuning for Arch, Debian/Ubuntu,
#  Fedora and openSUSE (incl. derivatives via ID_LIKE).
#
#  Bilingual: German/English — auto-detected via $LANG, override: --lang=de|en
#
#  15 modules:
#    Update (PM/AUR/Flatpak/Snap/fwupd) · Deep Cleanup · Mirror Optimization
#    sysctl Tuning (VM/BBR/latency) · I/O Scheduler · CPU Governor · ZRAM
#    Service Audit · SSD TRIM · Gaming · DNS (DoT) · Btrfs Maintenance
#    Security Quickcheck · Auto-Maintenance Timer · Health Report
#
#  Modes:  TUI menu  |  --all  |  --dry-run  |  --revert  |  --help
#  Everything the script creates is prefixed "adhyper" and fully revertible
#  via --revert (backups: /etc/adhyper-backup).
# ============================================================================

set -uo pipefail

SCRIPT_VERSION="1.2.0"
BACKUP_DIR="/etc/adhyper-backup"
STATE_FILE="${BACKUP_DIR}/state.list"
LOG_FILE="/var/log/adhyper-optimize.log"
INSTALL_PATH="/usr/local/bin/adhyper-linux"
DRY_RUN=0
ASSUME_YES=0
UI_LANG=""

# ---------------------------------------------------------------- colors ---
if [[ -t 1 ]]; then
    C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_B=$'\e[38;5;39m'
    C_C=$'\e[36m'; C_M=$'\e[35m'; C_W=$'\e[97m'; C_D=$'\e[2m'; C_0=$'\e[0m'
    C_BOLD=$'\e[1m'; C_ACC=$'\e[38;5;45m'; C_HDR=$'\e[38;5;208m'
else
    C_R=""; C_G=""; C_Y=""; C_B=""; C_C=""; C_M=""; C_W=""; C_D=""; C_0=""
    C_BOLD=""; C_ACC=""; C_HDR=""
fi

# ------------------------------------------------------------------ i18n ---
declare -A L

set_lang() {
    if [[ -z "$UI_LANG" ]]; then
        local sys="${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}"
        [[ "$sys" == de* ]] && UI_LANG="de" || UI_LANG="en"
    fi

    if [[ "$UI_LANG" == "de" ]]; then
        L[yn]="[j/N]"
        L[pause]="[Enter] zurück zum Menü..."
        L[written]="geschrieben:"
        L[no_pm]="Kein unterstützter Paketmanager gefunden."
        L[no_root]="Ohne root — einige Checks eingeschränkt."
        L[unknown_opt]="Unbekannte Option:"
        L[step]="Schritt"
        # update
        L[m1]="System-Update"
        L[aur_via]="AUR-Update via"
        L[as_user]="als"
        L[pacnew]=".pacnew-Dateien gefunden — manuell mergen:"
        L[flatpak_up]="Flatpak-Update"
        L[snap_up]="Snap-Update"
        L[fw_up]="Firmware-Update (fwupd)"
        L[fw_missing]="fwupd nicht installiert — Firmware-Updates übersprungen (Install: fwupd)"
        L[reboot_req]="Reboot erforderlich (Kernel/Core-Update)."
        L[update_done]="Update abgeschlossen."
        # cleanup
        L[m2]="Deep Cleanup"
        L[orphans]="Orphans:"
        L[pkgs]="Pakete"
        L[no_orphans]="Keine Orphan-Pakete."
        L[paccache_missing]="paccache fehlt (pacman-contrib) — Cache-Trim übersprungen"
        L[snap_old]="Alte Snap-Revisionen entfernen"
        L[journal_lim]="Journal auf 100 MB / 2 Wochen begrenzen"
        L[coredumps]="Coredumps & Crash-Reports"
        L[tmp_clean]="Temp-Verzeichnisse (Dateien älter als 7 Tage)"
        L[user_cache]="User-Cache"
        L[cleanup_done]="Cleanup fertig — freigegeben:"
        # mirrors
        L[m3]="Mirror- & Paketmanager-Optimierung"
        L[pacman_par]="pacman: ParallelDownloads=10, Color aktiviert."
        L[ask_reflector]="reflector installieren (schnellste Mirrors automatisch)?"
        L[ranking]="Mirrors ranken (HTTPS, letzte 12h, nach Rate)..."
        L[mirrorlist_ok]="Mirrorlist aktualisiert."
        L[apt_mirror1]="apt nutzt bereits die Distro-Mirror-Auswahl."
        L[apt_mirror2]="Tipp: In den 'Anwendungspaketquellen' den Server auf 'Beste Server' stellen (Mint/Ubuntu-GUI)."
        L[dnf_ok]="dnf: parallele Downloads + fastestmirror aktiv."
        L[zypper_mirror]="zypper: Mirror-Auswahl läuft über MirrorCache/CDN — nichts zu tun."
        # sysctl
        L[m4]="Kernel-/sysctl-Tuning"
        L[zram_det]="ZRAM erkannt → swappiness=100, page-cluster=0"
        L[no_zram_det]="Kein ZRAM → swappiness=10"
        L[bbr_ok]="BBR verfügbar → aktiviere BBR + fq"
        L[bbr_no]="BBR nicht verfügbar → fq_codel bleibt"
        L[sysctl_ok]="sysctl-Tuning aktiv."
        # iosched
        L[m5]="I/O-Scheduler (udev)"
        L[devices]="Geräte:"
        L[iosched_ok]="I/O-Scheduler-Regeln aktiv."
        # cpugov
        L[m6]="CPU-Governor"
        L[no_cpufreq]="Kein cpufreq-Interface (VM/Container?) — übersprungen."
        L[current]="aktuell"
        L[available]="verfügbar"
        L[laptop_warn]="Laptop erkannt — 'performance' dauerhaft kostet Akku."
        L[ask_perf_laptop]="Trotzdem 'performance' setzen? (Nein = Governor belassen)"
        L[ask_perf]="Governor 'performance' dauerhaft setzen? (empfohlen für Desktop/Gaming-Rig)"
        L[gov_unchanged]="Governor unverändert."
        L[gov_navail]="nicht verfügbar bei Driver"
        L[skipped]="übersprungen."
        L[gov_ok]="gesetzt (persistiert via systemd-Service)."
        # zram
        L[m7]="ZRAM (komprimierter Swap im RAM)"
        L[zram_foreign]="zram0 existiert bereits (fremdes Setup: zramswap/zram-config?) — übersprungen um Konflikte zu vermeiden."
        L[zram_inst]="Installiere zram-generator"
        L[zram_active]="ZRAM aktiv:"
        L[after_reboot]="nach Reboot aktiv"
        L[zram_hint]="Hinweis: sysctl-Modul danach (erneut) ausführen → swappiness wird auf 100 angepasst."
        L[zram_tools_ok]="ZRAM via zram-tools aktiv."
        L[zram_fail]="Kein zram-generator/zram-tools installierbar — übersprungen."
        # services
        L[m8]="Service-Audit"
        L[boot_time]="Boot-Zeit:"
        L[top10]="Top 10 langsamste Boot-Services:"
        L[svc_nm_wait]="Wartet beim Boot auf Netzwerk (~5-15s Bootzeit)"
        L[svc_networkd_wait]="Wartet beim Boot auf Netzwerk"
        L[svc_modem]="Mobilfunk-Modems — ohne WWAN-Karte unnötig"
        L[svc_avahi]="mDNS/Zeroconf — nur für lokale Discovery (Drucker/Chromecast) nötig"
        L[svc_cups]="Druckdienst — wird bei Bedarf socket-aktiviert (cups.socket bleibt an)"
        L[svc_bt]="Bluetooth — nur deaktivieren wenn ungenutzt"
        L[svc_pk]="GUI-Paket-Backend — bei CLI-only-Nutzung unnötig"
        L[ask_disable]="→ deaktivieren?"
        L[no_svc_changes]="Keine Änderungen an Services."
        L[failed_units]="Fehlgeschlagene Units:"
        # trim
        L[m9]="SSD-TRIM"
        L[trim_ok]="fstrim.timer aktiv (wöchentlich)."
        L[trim_now]="Einmaliger Trim jetzt:"
        L[no_ssd]="Keine SSD erkannt — übersprungen."
        # gaming
        L[m10]="Gaming-Tweaks"
        L[ask_gamemode]="Feral GameMode installieren? (CPU-Governor/Prio automatisch beim Spielen)"
        L[gm_usage]="Nutzung: gamemoderun %command%  (Steam-Startoption)"
        L[gm_present]="GameMode bereits installiert."
        L[esync_ok]="esync-Limits gesetzt (wirksam nach Re-Login)."
        L[sysctl_missing]="sysctl-Modul noch nicht gelaufen — max_map_count/split_lock-Tweaks fehlen noch."
        L[mitig_warn1]="Optional: CPU-Mitigations abschalten (bis ~5-10% Perf, ABER: Spectre/Meltdown-Schutz weg)."
        L[mitig_warn2]="Nur auf reinen Gaming-Maschinen ohne sensible Daten sinnvoll."
        L[ask_mitig]="Kernel-Parameter 'mitigations=off' setzen?"
        L[mitig_set]="mitigations=off gesetzt — aktiv nach Reboot."
        L[mitig_already]="mitigations=off bereits gesetzt."
        L[sdboot_warn]="systemd-boot erkannt — 'mitigations=off' manuell in /boot/loader/entries/*.conf an 'options' anhängen."
        L[bl_unknown]="Bootloader nicht erkannt — Parameter manuell setzen."
        L[nvidia_det]="NVIDIA erkannt:"
        L[nv1]="Treiber aktuell? → nvidia-smi"
        L[nv2]="Shader-Cache behalten: __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1"
        L[nv3]="Bei Stottern: nvidia-drm.modeset=1 als Kernel-Param prüfen"
        L[amd_det]="AMD-GPU erkannt — Mesa aktuell halten; RADV ist Default-Vulkan-Treiber."
        L[gaming_done]="Gaming-Tweaks fertig."
        # dns
        L[m11]="DNS-Optimierung (Cloudflare/Quad9 + DNS-over-TLS)"
        L[resolved_missing]="systemd-resolved läuft nicht — DNS-Modul übersprungen."
        L[resolved_alt]="Alternative: DNS im NetworkManager/Router auf 1.1.1.1 / 9.9.9.9 stellen."
        L[dns_info]="Setzt: Cloudflare (1.1.1.1) primär, Quad9 (9.9.9.9) Fallback, DoT opportunistic."
        L[ask_dns]="DNS-Server systemweit ändern?"
        L[dns_ok]="DNS umgestellt (revertierbar)."
        # btrfs
        L[m12]="Btrfs-Wartung"
        L[not_btrfs]="kein Btrfs — übersprungen."
        L[root_fs]="Root-FS ist"
        L[btrfs_det]="Btrfs-Root erkannt. Belegung:"
        L[ask_balance]="Balance ausführen? (defragmentiert Chunk-Allokation, dauert wenige Minuten)"
        L[balance_done]="Balance fertig."
        L[ask_scrub]="Scrub starten? (prüft Checksummen, läuft im Hintergrund)"
        L[scrub_status]="Status: btrfs scrub status /"
        L[compress_tip]="Tipp: 'compress=zstd:1' als Mount-Option in /etc/fstab spart Platz + oft schneller."
        L[ask_scrub_timer]="Monatlichen Scrub-Timer aktivieren?"
        # security
        L[m13]="Security-Quickcheck (nur Analyse, ändert nichts)"
        L[fw_hdr]="— Firewall —"
        L[no_fw]="Keine aktive Firewall erkannt (ufw/firewalld/nftables)."
        L[ssh_hdr]="— SSH —"
        L[no_ssh]="Kein SSH-Server aktiv."
        L[root_login_warn]="SSH-Root-Login erlaubt — 'PermitRootLogin no' empfohlen."
        L[pw_auth_info]="Passwort-Auth aktiv — Keys sind sicherer."
        L[ports_hdr]="— Offene Ports (listening) —"
        L[autoupd_hdr]="— Auto-Updates —"
        L[unatt_ok]="unattended-upgrades installiert."
        L[unatt_tip]="Tipp: 'unattended-upgrades' für automatische Security-Patches."
        L[dnf_auto_ok]="dnf-automatic aktiv."
        L[dnf_auto_tip]="Tipp: dnf-automatic für automatische Security-Patches."
        L[arch_tip]="Rolling Release — regelmäßig 'pacman -Syu' (oder Modul 1) reicht."
        L[zypper_tip]="Tipp: 'zypper patch' regelmäßig oder YaST Online-Update."
        L[logins_hdr]="— Letzte fehlgeschlagene Logins —"
        L[no_data]="(keine Daten)"
        L[sec_done]="Security-Check fertig."
        # automaint
        L[m14]="Auto-Maintenance-Timer"
        L[maint_info1]="Installiert das Script nach"
        L[maint_info2]="und richtet einen wöchentlichen systemd-Timer ein: Cleanup, vollautomatisch."
        L[ask_setup]="Einrichten?"
        L[timer_ok]="Timer aktiv: sonntags 04:00 Uhr. Status: systemctl list-timers adhyper*"
        # health
        L[m15]="System-Health-Report"
        L[mem_hdr]="— Speicher —"
        L[disk_hdr]="— Disks —"
        L[failed_hdr]="— Fehlgeschlagene Units —"
        L[jerr_hdr]="— Journal-Errors (letzter Boot, max 15) —"
        L[smart_hdr]="— SMART —"
        L[smart_missing]="smartmontools nicht installiert — SMART-Check übersprungen."
        L[unknown]="unbekannt"
        L[temps_hdr]="— Temperaturen —"
        L[tweaks_hdr]="— Aktive Tweaks (adhyper) —"
        L[none]="keine"
        L[report_done]="Report fertig. Log:"
        # revert
        L[rev_title]="Revert aller AD-HyperOptimize-Tweaks"
        L[no_state]="Kein State-File — nichts zu reverten."
        L[ask_revert]="Wirklich alle Tweaks zurücknehmen?"
        L[removed]="entfernt:"
        L[restored]="wiederhergestellt:"
        L[reenabled]="reaktiviert:"
        L[rev_grub]="Falls mitigations=off gesetzt war → GRUB-Config wurde restauriert. Reboot empfohlen."
        L[rev_done]="Revert abgeschlossen."
        # menu
        L[cat1]="UPDATE & WARTUNG"
        L[cat2]="PERFORMANCE"
        L[cat3]="EXTRAS"
        L[mi1]="System-Update";       L[md1]="Pakete · AUR · Flatpak · Snap · Firmware"
        L[mi2]="Deep Cleanup";        L[md2]="Orphans · Caches · Logs · alte Kernel"
        L[mi3]="Mirror-Optimierung";  L[md3]="schnellste Mirrors · parallele Downloads"
        L[mi4]="Kernel/sysctl";       L[md4]="VM · Netzwerk/BBR · Latenz"
        L[mi5]="I/O-Scheduler";       L[md5]="NVMe→none · SSD→mq-deadline · HDD→bfq"
        L[mi6]="CPU-Governor";        L[md6]="performance, persistent"
        L[mi7]="ZRAM";                L[md7]="zstd-Swap im RAM, bis 8 GB"
        L[mi8]="Service-Audit";       L[md8]="Boot-Analyse · unnötige Dienste"
        L[mi9]="SSD-TRIM";            L[md9]="fstrim.timer"
        L[mi10]="Gaming-Tweaks";      L[md10]="GameMode · esync · mitigations opt-in"
        L[mi11]="DNS-Optimierung";    L[md11]="Cloudflare/Quad9 · DNS-over-TLS"
        L[mi12]="Btrfs-Wartung";      L[md12]="Balance · Scrub · Compression-Check"
        L[mi13]="Security-Check";     L[md13]="Firewall · SSH · offene Ports (read-only)"
        L[mi14]="Auto-Maintenance";   L[md14]="wöchentlicher Cleanup-Timer"
        L[mi15]="Health-Report";      L[md15]="SMART · failed units · Temps"
        L[run_all]="ALLES ausführen"
        L[revert]="Revert"
        L[dryrun]="Dry-Run"
        L[on]="[AN]"
        L[off]="[aus]"
        L[quit]="Ende"
        L[active]="aktiv"
    else
        L[yn]="[y/N]"
        L[pause]="[Enter] back to menu..."
        L[written]="written:"
        L[no_pm]="No supported package manager found."
        L[no_root]="Running without root — some checks limited."
        L[unknown_opt]="Unknown option:"
        L[step]="Step"
        # update
        L[m1]="System Update"
        L[aur_via]="AUR update via"
        L[as_user]="as"
        L[pacnew]=".pacnew files found — merge manually:"
        L[flatpak_up]="Flatpak update"
        L[snap_up]="Snap update"
        L[fw_up]="Firmware update (fwupd)"
        L[fw_missing]="fwupd not installed — firmware updates skipped (install: fwupd)"
        L[reboot_req]="Reboot required (kernel/core update)."
        L[update_done]="Update finished."
        # cleanup
        L[m2]="Deep Cleanup"
        L[orphans]="Orphans:"
        L[pkgs]="packages"
        L[no_orphans]="No orphan packages."
        L[paccache_missing]="paccache missing (pacman-contrib) — cache trim skipped"
        L[snap_old]="Removing old snap revisions"
        L[journal_lim]="Limiting journal to 100 MB / 2 weeks"
        L[coredumps]="Coredumps & crash reports"
        L[tmp_clean]="Temp directories (files older than 7 days)"
        L[user_cache]="User cache"
        L[cleanup_done]="Cleanup done — freed:"
        # mirrors
        L[m3]="Mirror & Package Manager Optimization"
        L[pacman_par]="pacman: ParallelDownloads=10, Color enabled."
        L[ask_reflector]="Install reflector (fastest mirrors automatically)?"
        L[ranking]="Ranking mirrors (HTTPS, last 12h, by rate)..."
        L[mirrorlist_ok]="Mirrorlist updated."
        L[apt_mirror1]="apt already uses the distro mirror selection."
        L[apt_mirror2]="Tip: In 'Software Sources' set the server to 'Best server' (Mint/Ubuntu GUI)."
        L[dnf_ok]="dnf: parallel downloads + fastestmirror enabled."
        L[zypper_mirror]="zypper: mirror selection handled by MirrorCache/CDN — nothing to do."
        # sysctl
        L[m4]="Kernel/sysctl Tuning"
        L[zram_det]="ZRAM detected → swappiness=100, page-cluster=0"
        L[no_zram_det]="No ZRAM → swappiness=10"
        L[bbr_ok]="BBR available → enabling BBR + fq"
        L[bbr_no]="BBR not available → keeping fq_codel"
        L[sysctl_ok]="sysctl tuning active."
        # iosched
        L[m5]="I/O Scheduler (udev)"
        L[devices]="Devices:"
        L[iosched_ok]="I/O scheduler rules active."
        # cpugov
        L[m6]="CPU Governor"
        L[no_cpufreq]="No cpufreq interface (VM/container?) — skipped."
        L[current]="current"
        L[available]="available"
        L[laptop_warn]="Laptop detected — permanent 'performance' drains battery."
        L[ask_perf_laptop]="Set 'performance' anyway? (No = keep current governor)"
        L[ask_perf]="Set 'performance' governor permanently? (recommended for desktop/gaming rig)"
        L[gov_unchanged]="Governor unchanged."
        L[gov_navail]="not available with driver"
        L[skipped]="skipped."
        L[gov_ok]="set (persisted via systemd service)."
        # zram
        L[m7]="ZRAM (compressed swap in RAM)"
        L[zram_foreign]="zram0 already exists (foreign setup: zramswap/zram-config?) — skipped to avoid conflicts."
        L[zram_inst]="Installing zram-generator"
        L[zram_active]="ZRAM active:"
        L[after_reboot]="active after reboot"
        L[zram_hint]="Note: re-run the sysctl module afterwards → swappiness will be adjusted to 100."
        L[zram_tools_ok]="ZRAM active via zram-tools."
        L[zram_fail]="Neither zram-generator nor zram-tools installable — skipped."
        # services
        L[m8]="Service Audit"
        L[boot_time]="Boot time:"
        L[top10]="Top 10 slowest boot services:"
        L[svc_nm_wait]="Waits for network at boot (~5-15s boot time)"
        L[svc_networkd_wait]="Waits for network at boot"
        L[svc_modem]="Cellular modems — useless without a WWAN card"
        L[svc_avahi]="mDNS/Zeroconf — only needed for local discovery (printers/Chromecast)"
        L[svc_cups]="Print service — socket-activated on demand (cups.socket stays on)"
        L[svc_bt]="Bluetooth — only disable if unused"
        L[svc_pk]="GUI package backend — unnecessary for CLI-only usage"
        L[ask_disable]="→ disable?"
        L[no_svc_changes]="No service changes."
        L[failed_units]="Failed units:"
        # trim
        L[m9]="SSD TRIM"
        L[trim_ok]="fstrim.timer active (weekly)."
        L[trim_now]="One-time trim now:"
        L[no_ssd]="No SSD detected — skipped."
        # gaming
        L[m10]="Gaming Tweaks"
        L[ask_gamemode]="Install Feral GameMode? (auto CPU governor/priority while gaming)"
        L[gm_usage]="Usage: gamemoderun %command%  (Steam launch option)"
        L[gm_present]="GameMode already installed."
        L[esync_ok]="esync limits set (effective after re-login)."
        L[sysctl_missing]="sysctl module not run yet — max_map_count/split_lock tweaks still missing."
        L[mitig_warn1]="Optional: disable CPU mitigations (up to ~5-10% perf, BUT: no Spectre/Meltdown protection)."
        L[mitig_warn2]="Only sensible on pure gaming machines without sensitive data."
        L[ask_mitig]="Set kernel parameter 'mitigations=off'?"
        L[mitig_set]="mitigations=off set — active after reboot."
        L[mitig_already]="mitigations=off already set."
        L[sdboot_warn]="systemd-boot detected — append 'mitigations=off' manually to 'options' in /boot/loader/entries/*.conf."
        L[bl_unknown]="Bootloader not detected — set the parameter manually."
        L[nvidia_det]="NVIDIA detected:"
        L[nv1]="Driver up to date? → nvidia-smi"
        L[nv2]="Keep shader cache: __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1"
        L[nv3]="On stutter: check nvidia-drm.modeset=1 as kernel param"
        L[amd_det]="AMD GPU detected — keep Mesa up to date; RADV is the default Vulkan driver."
        L[gaming_done]="Gaming tweaks done."
        # dns
        L[m11]="DNS Optimization (Cloudflare/Quad9 + DNS-over-TLS)"
        L[resolved_missing]="systemd-resolved is not running — DNS module skipped."
        L[resolved_alt]="Alternative: set DNS to 1.1.1.1 / 9.9.9.9 in NetworkManager/router."
        L[dns_info]="Sets: Cloudflare (1.1.1.1) primary, Quad9 (9.9.9.9) fallback, DoT opportunistic."
        L[ask_dns]="Change DNS servers system-wide?"
        L[dns_ok]="DNS switched (revertible)."
        # btrfs
        L[m12]="Btrfs Maintenance"
        L[not_btrfs]="not Btrfs — skipped."
        L[root_fs]="Root FS is"
        L[btrfs_det]="Btrfs root detected. Usage:"
        L[ask_balance]="Run balance? (defragments chunk allocation, takes a few minutes)"
        L[balance_done]="Balance done."
        L[ask_scrub]="Start scrub? (verifies checksums, runs in background)"
        L[scrub_status]="Status: btrfs scrub status /"
        L[compress_tip]="Tip: 'compress=zstd:1' as mount option in /etc/fstab saves space + is often faster."
        L[ask_scrub_timer]="Enable monthly scrub timer?"
        # security
        L[m13]="Security Quickcheck (analysis only, changes nothing)"
        L[fw_hdr]="— Firewall —"
        L[no_fw]="No active firewall detected (ufw/firewalld/nftables)."
        L[ssh_hdr]="— SSH —"
        L[no_ssh]="No SSH server active."
        L[root_login_warn]="SSH root login allowed — 'PermitRootLogin no' recommended."
        L[pw_auth_info]="Password auth active — keys are safer."
        L[ports_hdr]="— Open ports (listening) —"
        L[autoupd_hdr]="— Auto updates —"
        L[unatt_ok]="unattended-upgrades installed."
        L[unatt_tip]="Tip: 'unattended-upgrades' for automatic security patches."
        L[dnf_auto_ok]="dnf-automatic active."
        L[dnf_auto_tip]="Tip: dnf-automatic for automatic security patches."
        L[arch_tip]="Rolling release — regular 'pacman -Syu' (or module 1) is enough."
        L[zypper_tip]="Tip: run 'zypper patch' regularly or YaST online update."
        L[logins_hdr]="— Recent failed logins —"
        L[no_data]="(no data)"
        L[sec_done]="Security check done."
        # automaint
        L[m14]="Auto-Maintenance Timer"
        L[maint_info1]="Installs the script to"
        L[maint_info2]="and sets up a weekly systemd timer: cleanup, fully automatic."
        L[ask_setup]="Set it up?"
        L[timer_ok]="Timer active: Sundays 04:00. Status: systemctl list-timers adhyper*"
        # health
        L[m15]="System Health Report"
        L[mem_hdr]="— Memory —"
        L[disk_hdr]="— Disks —"
        L[failed_hdr]="— Failed units —"
        L[jerr_hdr]="— Journal errors (last boot, max 15) —"
        L[smart_hdr]="— SMART —"
        L[smart_missing]="smartmontools not installed — SMART check skipped."
        L[unknown]="unknown"
        L[temps_hdr]="— Temperatures —"
        L[tweaks_hdr]="— Active tweaks (adhyper) —"
        L[none]="none"
        L[report_done]="Report done. Log:"
        # revert
        L[rev_title]="Revert all AD HyperOptimize tweaks"
        L[no_state]="No state file — nothing to revert."
        L[ask_revert]="Really revert all tweaks?"
        L[removed]="removed:"
        L[restored]="restored:"
        L[reenabled]="re-enabled:"
        L[rev_grub]="If mitigations=off was set → GRUB config was restored. Reboot recommended."
        L[rev_done]="Revert finished."
        # menu
        L[cat1]="UPDATE & MAINTENANCE"
        L[cat2]="PERFORMANCE"
        L[cat3]="EXTRAS"
        L[mi1]="System Update";       L[md1]="packages · AUR · Flatpak · Snap · firmware"
        L[mi2]="Deep Cleanup";        L[md2]="orphans · caches · logs · old kernels"
        L[mi3]="Mirror Optimization"; L[md3]="fastest mirrors · parallel downloads"
        L[mi4]="Kernel/sysctl";       L[md4]="VM · network/BBR · latency"
        L[mi5]="I/O Scheduler";       L[md5]="NVMe→none · SSD→mq-deadline · HDD→bfq"
        L[mi6]="CPU Governor";        L[md6]="performance, persistent"
        L[mi7]="ZRAM";                L[md7]="zstd swap in RAM, up to 8 GB"
        L[mi8]="Service Audit";       L[md8]="boot analysis · unneeded services"
        L[mi9]="SSD TRIM";            L[md9]="fstrim.timer"
        L[mi10]="Gaming Tweaks";      L[md10]="GameMode · esync · mitigations opt-in"
        L[mi11]="DNS Optimization";   L[md11]="Cloudflare/Quad9 · DNS-over-TLS"
        L[mi12]="Btrfs Maintenance";  L[md12]="balance · scrub · compression check"
        L[mi13]="Security Check";     L[md13]="firewall · SSH · open ports (read-only)"
        L[mi14]="Auto-Maintenance";   L[md14]="weekly cleanup timer"
        L[mi15]="Health Report";      L[md15]="SMART · failed units · temps"
        L[run_all]="Run ALL"
        L[revert]="Revert"
        L[dryrun]="Dry run"
        L[on]="[ON]"
        L[off]="[off]"
        L[quit]="Quit"
        L[active]="active"
    fi
}

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

# backup_file <path> — back up original once
backup_file() {
    local path="$1"
    [[ $DRY_RUN -eq 1 || ! -f "$path" ]] && return 0
    if ! grep -qxF "RESTORE:${path}" "$STATE_FILE" 2>/dev/null; then
        mkdir -p "${BACKUP_DIR}$(dirname "$path")"
        cp -a "$path" "${BACKUP_DIR}${path}"
        track_state "RESTORE:${path}"
    fi
}

# write_file <path> <content> — with backup + state tracking, dry-run aware
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
    ok "${L[written]} $path"
}

ask() {  # ask "question" -> 0=yes 1=no  (accepts j/y in both languages)
    [[ $ASSUME_YES -eq 1 ]] && return 0
    local a
    read -rp "${C_Y}?${C_0} $1 ${L[yn]} " a
    [[ "$a" =~ ^([jJyY])$ ]]
}

# ask_safe: like ask, but with --all ALWAYS no (for risky options)
ask_safe() {
    [[ $ASSUME_YES -eq 1 ]] && return 1
    ask "$1"
}

pause() { [[ $ASSUME_YES -eq 1 ]] || read -rp "${C_D}${L[pause]}${C_0}"; }

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
    [[ -z "$PM" ]] && { err "${L[no_pm]}"; exit 1; }
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
#  MODULE 1: SYSTEM UPDATE
# ============================================================================
mod_update() {
    section "${L[m1]}"
    case "$PM" in
        pacman)
            run pacman -Syu --noconfirm
            if [[ -n "$AUR_HELPER" ]]; then
                info "${L[aur_via]} $AUR_HELPER (${L[as_user]} ${SUDO_USER:-root})"
                if [[ -n "${SUDO_USER:-}" && $DRY_RUN -eq 0 ]]; then
                    sudo -u "$SUDO_USER" "$AUR_HELPER" -Syu --noconfirm 2>&1 | tee -a "$LOG_FILE"
                else
                    run "$AUR_HELPER" -Syu --noconfirm
                fi
            fi
            local pacnews
            pacnews=$(find /etc -name '*.pacnew' 2>/dev/null)
            [[ -n "$pacnews" ]] && warn "${L[pacnew]}"$'\n'"$pacnews"
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
        info "${L[flatpak_up]}"
        run flatpak update -y
    fi
    if command -v snap &>/dev/null; then
        info "${L[snap_up]}"
        run snap refresh
    fi
    if command -v fwupdmgr &>/dev/null; then
        info "${L[fw_up]}"
        run fwupdmgr refresh --force
        run fwupdmgr update -y || true
    else
        warn "${L[fw_missing]}"
    fi

    if [[ -f /var/run/reboot-required ]] || { [[ "$PM" == pacman ]] && [[ -e /usr/lib/modules ]] && ! ls "/usr/lib/modules/$(uname -r)" &>/dev/null; }; then
        warn "${L[reboot_req]}"
    fi
    ok "${L[update_done]}"
}

# ============================================================================
#  MODULE 2: DEEP CLEANUP
# ============================================================================
mod_cleanup() {
    section "${L[m2]}"
    local before after
    before=$(df --output=avail -B1 / | tail -1)

    case "$PM" in
        pacman)
            local orphans
            orphans=$(pacman -Qtdq 2>/dev/null || true)
            if [[ -n "$orphans" ]]; then
                info "${L[orphans]} $(echo "$orphans" | wc -l) ${L[pkgs]}"
                # shellcheck disable=SC2086
                run pacman -Rns --noconfirm $orphans
            else
                ok "${L[no_orphans]}"
            fi
            if command -v paccache &>/dev/null; then
                run paccache -rk2
                run paccache -ruk0
            else
                warn "${L[paccache_missing]}"
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
        info "${L[snap_old]}"
        if [[ $DRY_RUN -eq 0 ]]; then
            snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | \
            while read -r name rev; do
                snap remove "$name" --revision="$rev" 2>&1 | tee -a "$LOG_FILE"
            done
            snap set system refresh.retain=2 2>/dev/null || true
        else
            echo "${C_M}[dry-run]${C_0} snap: remove disabled revisions, retain=2"
        fi
    fi

    info "${L[journal_lim]}"
    run journalctl --vacuum-size=100M
    run journalctl --vacuum-time=2weeks

    info "${L[coredumps]}"
    run rm -rf /var/lib/systemd/coredump/*
    [[ -d /var/crash ]] && run rm -rf /var/crash/*

    info "${L[tmp_clean]}"
    run find /tmp -mindepth 1 -mtime +7 -delete
    run find /var/tmp -mindepth 1 -mtime +7 -delete

    if [[ -n "${SUDO_USER:-}" ]]; then
        local uhome
        uhome=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        if [[ -d "$uhome" ]]; then
            info "${L[user_cache]} ($SUDO_USER): Thumbnails + Trash>30d"
            run rm -rf "$uhome/.cache/thumbnails"
            [[ -d "$uhome/.local/share/Trash/files" ]] && \
                run find "$uhome/.local/share/Trash/files" -mindepth 1 -mtime +30 -exec rm -rf {} +
        fi
    fi

    after=$(df --output=avail -B1 / | tail -1)
    local freed=$(( (after - before) / 1024 / 1024 ))
    (( freed < 0 )) && freed=0
    ok "${L[cleanup_done]} ~${freed} MB"
}

# ============================================================================
#  MODULE 3: MIRROR & PACKAGE MANAGER OPTIMIZATION
# ============================================================================
mod_mirrors() {
    section "${L[m3]}"
    case "$PM" in
        pacman)
            if grep -qE '^#?ParallelDownloads' /etc/pacman.conf 2>/dev/null; then
                backup_file /etc/pacman.conf
                if [[ $DRY_RUN -eq 0 ]]; then
                    sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
                    sed -i 's/^#Color$/Color/' /etc/pacman.conf
                fi
                ok "${L[pacman_par]}"
            fi
            if ! command -v reflector &>/dev/null; then
                ask "${L[ask_reflector]}" && pkg_install reflector
            fi
            if command -v reflector &>/dev/null; then
                backup_file /etc/pacman.d/mirrorlist
                info "${L[ranking]}"
                run reflector --age 12 --protocol https --sort rate --latest 20 --save /etc/pacman.d/mirrorlist
                ok "${L[mirrorlist_ok]}"
            fi
            ;;
        apt)
            info "${L[apt_mirror1]}"
            info "${L[apt_mirror2]}"
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
            ok "${L[dnf_ok]}"
            ;;
        zypper)
            info "${L[zypper_mirror]}"
            ;;
    esac
}

# ============================================================================
#  MODULE 4: KERNEL / SYSCTL TUNING
# ============================================================================
mod_sysctl() {
    section "${L[m4]}"

    local ram_kb ram_gb swappiness pagecluster
    ram_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    ram_gb=$(( ram_kb / 1024 / 1024 ))

    if [[ -e /dev/zram0 ]] || [[ -f /etc/systemd/zram-generator.conf ]]; then
        swappiness=100; pagecluster=0
        info "${L[zram_det]}"
    else
        swappiness=10; pagecluster=3
        info "${L[no_zram_det]}"
    fi

    local qdisc="fq_codel" cc=""
    if modprobe tcp_bbr 2>/dev/null || grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        cc="net.ipv4.tcp_congestion_control = bbr"
        qdisc="fq"
        ok "${L[bbr_ok]}"
    else
        warn "${L[bbr_no]}"
    fi

    local splitlock=""
    [[ -e /proc/sys/kernel/split_lock_mitigate ]] && splitlock="kernel.split_lock_mitigate = 0"

    write_file /etc/sysctl.d/99-adhyper-tuning.conf "\
# AD HyperOptimize — kernel tuning (RAM: ${ram_gb} GB)
# Revert: adhyper-linux.sh --revert

## --- Virtual memory ---
vm.swappiness = ${swappiness}
vm.page-cluster = ${pagecluster}
# Keep dentry/inode cache longer (desktop responsiveness)
vm.vfs_cache_pressure = 50
# Absolute dirty limits instead of percent -> no multi-GB writeback stalls
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 134217728
vm.dirty_writeback_centisecs = 1500
# Memory maps for games/Wine/ASAN
vm.max_map_count = 2147483642
# Less proactive compaction = fewer latency spikes
vm.compaction_proactiveness = 0
vm.watermark_boost_factor = 1
vm.watermark_scale_factor = 125

## --- Scheduler / latency ---
kernel.nmi_watchdog = 0
kernel.sched_autogroup_enabled = 1
${splitlock}

## --- Filesystem ---
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1024
fs.file-max = 2097152

## --- Network ---
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
    ok "${L[sysctl_ok]}"
}

# ============================================================================
#  MODULE 5: I/O SCHEDULER
# ============================================================================
mod_iosched() {
    section "${L[m5]}"
    info "${L[devices]}"
    lsblk -dno NAME,ROTA,TYPE 2>/dev/null | awk '$3=="disk"{print "   " $1 " -> " ($2==1 ? "HDD" : "SSD/NVMe")}'

    write_file /etc/udev/rules.d/60-adhyper-iosched.rules "\
# AD HyperOptimize — I/O scheduler per device type
# NVMe: 'none' — hardware queues, scheduler overhead unnecessary
ACTION==\"add|change\", KERNEL==\"nvme[0-9]*n[0-9]*\", ATTR{queue/scheduler}=\"none\"
# SATA/USB SSD: mq-deadline — low latency
ACTION==\"add|change\", KERNEL==\"sd[a-z]*|mmcblk[0-9]*\", ATTR{queue/rotational}==\"0\", ATTR{queue/scheduler}=\"mq-deadline\"
# HDD: bfq — fairness on rotational media
ACTION==\"add|change\", KERNEL==\"sd[a-z]*\", ATTR{queue/rotational}==\"1\", ATTR{queue/scheduler}=\"bfq\"
# Increase read-ahead for HDDs
ACTION==\"add|change\", KERNEL==\"sd[a-z]*\", ATTR{queue/rotational}==\"1\", ATTR{bdi/read_ahead_kb}=\"2048\""

    if [[ $DRY_RUN -eq 0 ]]; then
        udevadm control --reload-rules
        udevadm trigger --subsystem-match=block
    fi
    ok "${L[iosched_ok]}"
}

# ============================================================================
#  MODULE 6: CPU GOVERNOR
# ============================================================================
mod_cpugov() {
    section "${L[m6]}"
    local gov_path=/sys/devices/system/cpu/cpu0/cpufreq
    if [[ ! -d $gov_path ]]; then
        warn "${L[no_cpufreq]}"
        return
    fi
    local driver current available target
    driver=$(cat "$gov_path/scaling_driver" 2>/dev/null || echo "?")
    current=$(cat "$gov_path/scaling_governor" 2>/dev/null || echo "?")
    available=$(cat "$gov_path/scaling_available_governors" 2>/dev/null || echo "?")
    info "Driver: $driver | ${L[current]}: $current | ${L[available]}: $available"

    if [[ $IS_LAPTOP -eq 1 ]]; then
        warn "${L[laptop_warn]}"
        if ask_safe "${L[ask_perf_laptop]}"; then
            target="performance"
        else
            info "${L[gov_unchanged]}"; return
        fi
    else
        target="performance"
        if ! ask "${L[ask_perf]}"; then
            info "${L[gov_unchanged]}"; return
        fi
    fi
    if ! grep -qw "$target" "$gov_path/scaling_available_governors" 2>/dev/null; then
        warn "'$target' ${L[gov_navail]} $driver — ${L[skipped]}"
        return
    fi

    write_file /etc/systemd/system/adhyper-cpugov.service "\
[Unit]
Description=AD HyperOptimize — CPU governor (${target})
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo ${target} > \$g; done; for e in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do [ -w \$e ] && echo performance > \$e || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target"

    run systemctl daemon-reload
    run systemctl enable --now adhyper-cpugov.service
    ok "Governor '$target' ${L[gov_ok]}"
}

# ============================================================================
#  MODULE 7: ZRAM
# ============================================================================
mod_zram() {
    section "${L[m7]}"
    if [[ -e /dev/zram0 ]] && ! [[ -f /etc/systemd/zram-generator.conf ]]; then
        warn "${L[zram_foreign]}"
        return
    fi

    if ! [[ -f /usr/lib/systemd/system-generators/zram-generator ]]; then
        info "${L[zram_inst]}"
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
        ok "${L[zram_active]} $(swapon --show=NAME,SIZE,PRIO --noheadings 2>/dev/null | grep zram || echo "${L[after_reboot]}")"
        info "${L[zram_hint]}"
    elif command -v zramswap &>/dev/null; then
        write_file /etc/default/zramswap "\
# AD HyperOptimize — ZRAM (zram-tools)
ALGO=zstd
PERCENT=50
PRIORITY=100"
        run systemctl enable --now zramswap.service
        ok "${L[zram_tools_ok]}"
    else
        err "${L[zram_fail]}"
    fi
}

# ============================================================================
#  MODULE 8: SERVICE AUDIT
# ============================================================================
mod_services() {
    section "${L[m8]}"
    info "${L[boot_time]}"
    systemd-analyze 2>/dev/null | tee -a "$LOG_FILE" || true
    info "${L[top10]}"
    systemd-analyze blame 2>/dev/null | head -10 | tee -a "$LOG_FILE" || true
    echo

    # SAFE = may be auto-disabled by --all
    local candidates=(
        "SAFE|NetworkManager-wait-online.service|${L[svc_nm_wait]}"
        "SAFE|systemd-networkd-wait-online.service|${L[svc_networkd_wait]}"
        "ASK|ModemManager.service|${L[svc_modem]}"
        "ASK|avahi-daemon.service|${L[svc_avahi]}"
        "ASK|cups.service|${L[svc_cups]}"
        "ASK|bluetooth.service|${L[svc_bt]}"
        "ASK|packagekit.service|${L[svc_pk]}"
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
                ask "  ${L[ask_disable]}" && doit=0
            else
                ask_safe "  ${L[ask_disable]}" && doit=0
            fi
            if [[ $doit -eq 0 ]]; then
                run systemctl disable --now "$svc"
                track_state "REENABLE:${svc}"
                touched=1
            fi
        fi
    done
    [[ $touched -eq 0 ]] && ok "${L[no_svc_changes]}"

    info "${L[failed_units]}"
    systemctl --failed --no-legend --no-pager 2>/dev/null | tee -a "$LOG_FILE" || true
}

# ============================================================================
#  MODULE 9: SSD TRIM
# ============================================================================
mod_trim() {
    section "${L[m9]}"
    if lsblk -dno ROTA 2>/dev/null | grep -qw 0; then
        run systemctl enable --now fstrim.timer
        ok "${L[trim_ok]}"
        [[ $DRY_RUN -eq 0 ]] && info "${L[trim_now]}" && run fstrim -av
    else
        warn "${L[no_ssd]}"
    fi
}

# ============================================================================
#  MODULE 10: GAMING TWEAKS
# ============================================================================
mod_gaming() {
    section "${L[m10]}"

    if ! command -v gamemoderun &>/dev/null; then
        if ask "${L[ask_gamemode]}"; then
            case "$PM" in
                pacman) pkg_install gamemode lib32-gamemode || pkg_install gamemode ;;
                *)      pkg_install gamemode ;;
            esac
            info "${L[gm_usage]}"
        fi
    else
        ok "${L[gm_present]}"
    fi

    write_file /etc/security/limits.d/99-adhyper-esync.conf "\
# AD HyperOptimize — high nofile limits for Wine/Proton esync
* hard nofile 1048576
* soft nofile 1048576"
    ok "${L[esync_ok]}"

    if [[ ! -f /etc/sysctl.d/99-adhyper-tuning.conf ]]; then
        warn "${L[sysctl_missing]}"
    fi

    echo
    warn "${L[mitig_warn1]}"
    warn "${L[mitig_warn2]}"
    if ask_safe "${L[ask_mitig]}"; then
        if [[ -f /etc/default/grub ]]; then
            if ! grep -q "mitigations=off" /etc/default/grub; then
                backup_file /etc/default/grub
                [[ $DRY_RUN -eq 0 ]] && sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 mitigations=off"/' /etc/default/grub
                if command -v update-grub &>/dev/null; then run update-grub
                elif command -v grub2-mkconfig &>/dev/null; then run grub2-mkconfig -o /boot/grub2/grub.cfg
                elif command -v grub-mkconfig &>/dev/null; then run grub-mkconfig -o /boot/grub/grub.cfg
                fi
                ok "${L[mitig_set]}"
            else
                ok "${L[mitig_already]}"
            fi
        elif [[ -d /boot/loader/entries ]]; then
            warn "${L[sdboot_warn]}"
        else
            warn "${L[bl_unknown]}"
        fi
    fi

    echo
    if lspci 2>/dev/null | grep -qi nvidia; then
        info "${L[nvidia_det]}"
        echo "   • ${L[nv1]}"
        echo "   • ${L[nv2]}"
        echo "   • ${L[nv3]}"
    fi
    if lspci 2>/dev/null | grep -iE "vga|3d" | grep -qiE "amd|ati|radeon"; then
        info "${L[amd_det]}"
    fi
    ok "${L[gaming_done]}"
}

# ============================================================================
#  MODULE 11: DNS (fast + encrypted)
# ============================================================================
mod_dns() {
    section "${L[m11]}"
    if ! systemctl is-active systemd-resolved &>/dev/null; then
        warn "${L[resolved_missing]}"
        info "${L[resolved_alt]}"
        return
    fi
    info "${L[dns_info]}"
    if ! ask_safe "${L[ask_dns]}"; then
        info "${L[skipped]}"; return
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
    ok "${L[dns_ok]}"
}

# ============================================================================
#  MODULE 12: BTRFS MAINTENANCE
# ============================================================================
mod_btrfs() {
    section "${L[m12]}"
    local fstype
    fstype=$(findmnt -no FSTYPE / 2>/dev/null || echo "")
    if [[ "$fstype" != "btrfs" ]]; then
        info "${L[root_fs]} ${fstype:-?}, ${L[not_btrfs]}"
        return
    fi

    info "${L[btrfs_det]}"
    btrfs filesystem usage / 2>/dev/null | head -8 || true
    echo

    if ask "${L[ask_balance]}"; then
        run btrfs balance start -dusage=50 -musage=50 /
        ok "${L[balance_done]}"
    fi
    if ask "${L[ask_scrub]}"; then
        run btrfs scrub start /
        info "${L[scrub_status]}"
    fi
    if ! grep -q "compress" /etc/fstab 2>/dev/null; then
        info "${L[compress_tip]}"
    fi
    if ! systemctl is-enabled btrfs-scrub@-.timer &>/dev/null 2>&1; then
        ask "${L[ask_scrub_timer]}" && run systemctl enable --now btrfs-scrub@-.timer || true
    fi
}

# ============================================================================
#  MODULE 13: SECURITY QUICKCHECK  (read-only)
# ============================================================================
mod_security() {
    section "${L[m13]}"

    echo "${C_W}${L[fw_hdr]}${C_0}"
    if command -v ufw &>/dev/null; then
        ufw status 2>/dev/null | head -3
    elif command -v firewall-cmd &>/dev/null; then
        echo "firewalld: $(firewall-cmd --state 2>/dev/null || echo '-')"
    elif command -v nft &>/dev/null && [[ -n "$(nft list ruleset 2>/dev/null)" ]]; then
        echo "nftables: active"
    else
        warn "${L[no_fw]}"
    fi

    echo; echo "${C_W}${L[ssh_hdr]}${C_0}"
    if [[ -f /etc/ssh/sshd_config ]] && systemctl is-active sshd &>/dev/null || systemctl is-active ssh &>/dev/null; then
        local prl pwa
        prl=$(sshd -T 2>/dev/null | awk '/^permitrootlogin/{print $2}')
        pwa=$(sshd -T 2>/dev/null | awk '/^passwordauthentication/{print $2}')
        echo "   PermitRootLogin: ${prl:-?}   PasswordAuthentication: ${pwa:-?}"
        [[ "${prl:-no}" == "yes" ]] && warn "${L[root_login_warn]}"
        [[ "${pwa:-no}" == "yes" ]] && info "${L[pw_auth_info]}"
    else
        echo "   ${L[no_ssh]}"
    fi

    echo; echo "${C_W}${L[ports_hdr]}${C_0}"
    ss -tulnH 2>/dev/null | awk '{printf "   %-6s %s\n", $1, $5}' | sort -u | head -15

    echo; echo "${C_W}${L[autoupd_hdr]}${C_0}"
    case "$PM" in
        apt)
            if dpkg -l unattended-upgrades &>/dev/null 2>&1; then
                echo "   ${L[unatt_ok]}"
            else
                info "${L[unatt_tip]}"
            fi ;;
        dnf)
            systemctl is-enabled dnf-automatic.timer &>/dev/null && echo "   ${L[dnf_auto_ok]}" || \
                info "${L[dnf_auto_tip]}" ;;
        pacman)
            info "${L[arch_tip]}" ;;
        zypper)
            info "${L[zypper_tip]}" ;;
    esac

    echo; echo "${C_W}${L[logins_hdr]}${C_0}"
    lastb -n 5 2>/dev/null | head -5 || echo "   ${L[no_data]}"
    ok "${L[sec_done]}"
}

# ============================================================================
#  MODULE 14: AUTO-MAINTENANCE (weekly timer)
# ============================================================================
mod_automaint() {
    section "${L[m14]}"
    info "${L[maint_info1]} ${INSTALL_PATH}"
    info "${L[maint_info2]}"
    if ! ask "${L[ask_setup]}"; then
        info "${L[skipped]}"; return
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
Description=AD HyperOptimize — weekly maintenance (cleanup)
After=network-online.target

[Service]
Type=oneshot
ExecStart=${INSTALL_PATH} --clean
Nice=19
IOSchedulingClass=idle"

    write_file /etc/systemd/system/adhyper-maintenance.timer "\
[Unit]
Description=AD HyperOptimize — weekly maintenance timer

[Timer]
OnCalendar=Sun 04:00
Persistent=true
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target"

    run systemctl daemon-reload
    run systemctl enable --now adhyper-maintenance.timer
    ok "${L[timer_ok]}"
}

# ============================================================================
#  MODULE 15: HEALTH REPORT
# ============================================================================
mod_health() {
    section "${L[m15]}"

    echo "${C_W}Host:${C_0} $(hostnamectl hostname 2>/dev/null || hostname) | ${C_W}Kernel:${C_0} $(uname -r) | ${C_W}Distro:${C_0} $DISTRO"
    echo "${C_W}Uptime:${C_0}$(uptime -p 2>/dev/null | sed 's/up//')"
    echo

    echo "${C_W}${L[mem_hdr]}${C_0}"
    free -h | tee -a "$LOG_FILE"
    echo
    echo "${C_W}${L[disk_hdr]}${C_0}"
    df -h -x tmpfs -x devtmpfs -x overlay 2>/dev/null | tee -a "$LOG_FILE"
    echo

    echo "${C_W}${L[failed_hdr]}${C_0}"
    systemctl --failed --no-pager 2>/dev/null | tee -a "$LOG_FILE" || true
    echo
    echo "${C_W}${L[jerr_hdr]}${C_0}"
    journalctl -p err -b --no-pager -n 15 2>/dev/null | tee -a "$LOG_FILE" || true
    echo

    if command -v smartctl &>/dev/null; then
        echo "${C_W}${L[smart_hdr]}${C_0}"
        for d in /dev/nvme[0-9]n1 /dev/sd[a-z]; do
            [[ -b "$d" ]] || continue
            local h
            h=$(smartctl -H "$d" 2>/dev/null | grep -iE "overall-health|SMART Health Status" | awk -F: '{print $2}' | xargs)
            echo "   $d: ${h:-${L[unknown]}}"
        done
    else
        warn "${L[smart_missing]}"
    fi

    if command -v sensors &>/dev/null; then
        echo; echo "${C_W}${L[temps_hdr]}${C_0}"
        sensors 2>/dev/null | grep -E "°C" | head -12
    fi

    echo
    echo "${C_W}${L[tweaks_hdr]}${C_0}"
    ls -1 /etc/sysctl.d/99-adhyper* /etc/udev/rules.d/60-adhyper* \
          /etc/systemd/system/adhyper* /etc/systemd/zram-generator.conf \
          /etc/security/limits.d/99-adhyper* /etc/systemd/resolved.conf.d/99-adhyper* 2>/dev/null || echo "   ${L[none]}"
    ok "${L[report_done]} $LOG_FILE"
}

# ============================================================================
#  REVERT
# ============================================================================
mod_revert() {
    section "${L[rev_title]}"
    if [[ ! -f "$STATE_FILE" ]]; then
        warn "${L[no_state]} ($STATE_FILE)"
        return
    fi
    ask "${L[ask_revert]}" || return

    if [[ $DRY_RUN -eq 0 ]]; then
        systemctl disable --now adhyper-cpugov.service 2>/dev/null || true
        systemctl disable --now adhyper-maintenance.timer 2>/dev/null || true
    fi

    while IFS=: read -r action target; do
        case "$action" in
            DELETE)
                if [[ -e "$target" ]]; then
                    run rm -f "$target"
                    ok "${L[removed]} $target"
                fi
                ;;
            RESTORE)
                local bk="${BACKUP_DIR}${target}"
                if [[ -f "$bk" ]]; then
                    run cp -a "$bk" "$target"
                    ok "${L[restored]} $target"
                fi
                ;;
            REENABLE)
                run systemctl enable --now "$target"
                ok "${L[reenabled]} $target"
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
    warn "${L[rev_grub]}"
    ok "${L[rev_done]}"
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
        echo; echo "${C_HDR}${C_BOLD}━━ ${L[step]} ${i}/${total} ━━${C_0}"
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

    echo " ${C_D}┌${C_0} RAM ${C_W}${mem_used}${C_0}${C_D}/${mem_total}${C_0}  Disk/ ${C_W}${disk_pct}${C_0}  Gov ${C_W}${gov}${C_0}  BBR ${bbr}  ZRAM ${zram}  Tweaks ${C_W}${tweaks}${C_0} ${L[active]}"
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
    echo " ${C_D}v${SCRIPT_VERSION} · ${DISTRO} · ${PM}$([[ -n $AUR_HELPER ]] && echo "+${AUR_HELPER}") · $(uname -r) · ${UI_LANG}$([[ $DRY_RUN -eq 1 ]] && echo " · ${C_M}${C_BOLD}DRY-RUN${C_0}${C_D}")${C_0}"
    dashboard
    hr
}

menu_item() { printf "  ${C_W}%3s${C_0}) %-22s ${C_D}%s${C_0}\n" "$1" "$2" "$3"; }

menu() {
    while true; do
        banner
        echo " ${C_HDR}${C_BOLD}◆ ${L[cat1]}${C_0}"
        menu_item 1  "${L[mi1]}"  "${L[md1]}"
        menu_item 2  "${L[mi2]}"  "${L[md2]}"
        menu_item 3  "${L[mi3]}"  "${L[md3]}"
        echo
        echo " ${C_HDR}${C_BOLD}◆ ${L[cat2]}${C_0}"
        menu_item 4  "${L[mi4]}"  "${L[md4]}"
        menu_item 5  "${L[mi5]}"  "${L[md5]}"
        menu_item 6  "${L[mi6]}"  "${L[md6]}"
        menu_item 7  "${L[mi7]}"  "${L[md7]}"
        menu_item 8  "${L[mi8]}"  "${L[md8]}"
        menu_item 9  "${L[mi9]}"  "${L[md9]}"
        menu_item 10 "${L[mi10]}" "${L[md10]}"
        echo
        echo " ${C_HDR}${C_BOLD}◆ ${L[cat3]}${C_0}"
        menu_item 11 "${L[mi11]}" "${L[md11]}"
        menu_item 12 "${L[mi12]}" "${L[md12]}"
        menu_item 13 "${L[mi13]}" "${L[md13]}"
        menu_item 14 "${L[mi14]}" "${L[md14]}"
        menu_item 15 "${L[mi15]}" "${L[md15]}"
        hr
        echo "   ${C_G}a${C_0}) ${L[run_all]}      ${C_Y}r${C_0}) ${L[revert]}      ${C_M}d${C_0}) ${L[dryrun]} $([[ $DRY_RUN -eq 1 ]] && echo "${C_M}${L[on]}${C_0}" || echo "${C_D}${L[off]}${C_0}")      ${C_R}q${C_0}) ${L[quit]}"
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
    if [[ "$UI_LANG" == "de" ]]; then
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
  --lang=de|en    Sprache erzwingen (Default: \$LANG)
  -h, --help      diese Hilfe
EOF
    else
        cat <<EOF
AD HyperOptimize — Linux Edition v${SCRIPT_VERSION}

Usage: sudo $0 [OPTION]
  (no option)     interactive menu
  --all           all core modules non-interactively (risky options stay off)
  --update        update only
  --clean         cleanup only
  --tune          zram + sysctl + iosched + trim
  --security      security quickcheck only
  --health        health report only
  --revert        revert all tweaks
  --dry-run       execute nothing, just show (combinable)
  --lang=de|en    force language (default: \$LANG)
  -h, --help      this help
EOF
    fi
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
            --lang=de)  UI_LANG="de" ;;
            --lang=en)  UI_LANG="en" ;;
            -h|--help)  set_lang; usage; exit 0 ;;
            *) set_lang; err "${L[unknown_opt]} $arg"; usage; exit 1 ;;
        esac
    done
    set_lang

    if [[ $EUID -eq 0 ]]; then
        touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/adhyper-optimize.log"
    else
        LOG_FILE="/tmp/adhyper-optimize.log"
        if [[ "$action" == "health" || "$action" == "security" || $DRY_RUN -eq 1 ]]; then
            warn "${L[no_root]}"
        else
            exec sudo -E "$0" "$@"
        fi
    fi
    log "=== AD HyperOptimize v${SCRIPT_VERSION} started (action=$action, dry-run=$DRY_RUN, lang=$UI_LANG) ==="

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
