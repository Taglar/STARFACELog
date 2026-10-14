
#!/bin/bash

# ============================================================
# STARFACE Log Collector
# Optimierte Version - direkte ZIP-Archivierung
# ============================================================

set -uo pipefail

# ------------------------------------------------------------
# Konfiguration
# ------------------------------------------------------------

START=$(date +%s)
DATUM=$(date '+%Y-%m-%d_%H-%M-%S')

ZIPPFAD="/tmp/logs_${DATUM}.zip"
ENTPACKPFAD="/tmp/SFLogs/${DATUM}"

# ZIP-Kompressionsstufe:
# 0 = keine Kompression (sehr schnell, große Datei)
# 1 = schnelle Kompression
# 6 = höhere Kompression
ZIP_LEVEL=1

# Temporäres Verzeichnis nur für Diagnoseberichte
WORKDIR=$(mktemp -d /tmp/sflogs.XXXXXXXX) || exit 1

# ------------------------------------------------------------
# Aufräumen bei Programmende
# ------------------------------------------------------------

cleanup() {
    rm -rf -- "$WORKDIR"
}

trap cleanup EXIT

# ZIP erhält relative Pfade ab /
cd / || exit 1

echo "============================================================"
echo "STARFACE LOG COLLECTOR"
echo "============================================================"
echo "Start:   $(date)"
echo "Archiv:  $ZIPPFAD"
echo

# ------------------------------------------------------------
# ZIP-Hilfsfunktion
# ------------------------------------------------------------

ZIP_ERRORS="$WORKDIR/zip-errors.log"
ZIP_FAILED=0

zip_add() {
    local description="$1"
    shift

    echo "📦 Archiviere: $description"

    if (( $# == 0 )); then
        return 0
    fi

    if ! zip -q "-${ZIP_LEVEL}" -r "$ZIPPFAD" "$@" \
        2>>"$ZIP_ERRORS"; then
        echo "⚠️ Fehler bei: $description"
        ZIP_FAILED=1
        return 1
    fi

    return 0
}

# ------------------------------------------------------------
# 1. Komplette Logverzeichnisse archivieren
# ------------------------------------------------------------

echo
echo "=== 1. Logverzeichnisse ==="

LOGDIRS=(
    "var/log/asterisk"
    "var/log/starface"
    "var/log/tomcat"
    "var/starface/fs-interface"
    "var/spool/hylafax/log"
)

for dir in "${LOGDIRS[@]}"; do
    if [[ -d "/$dir" ]]; then
        zip_add "$dir" "$dir" || true
    else
        echo "⏭️ Nicht vorhanden: /$dir"
    fi
done

# ------------------------------------------------------------
# 2. Openfire / PostgreSQL
# ------------------------------------------------------------

echo
echo "=== 2. Openfire / PostgreSQL ==="

# ZIP folgt standardmäßig symbolischen Links.
# Anders als rsync -L können dabei die im Archiv
# enthaltenen Pfade abweichen.

for dir in \
    "var/log/openfire" \
    "var/log/postgresql"
do
    if [[ -d "/$dir" ]]; then
        zip_add "$dir" "$dir" || true
    else
        echo "⏭️ Nicht vorhanden: /$dir"
    fi
done

# ------------------------------------------------------------
# 3. Einzelne Systemlogs
# ------------------------------------------------------------

echo
echo "=== 3. Weitere Systemlogs ==="

shopt -s nullglob

EXTRALOGS=(
    /var/log/messages*
    /var/log/maillog
    /var/log/kamailio.log*
)

RELLOGS=()

for file in "${EXTRALOGS[@]}"; do
    [[ -f "$file" ]] || continue
    RELLOGS+=("${file#/}")
done

if (( ${#RELLOGS[@]} > 0 )); then
    zip_add "Systemlogs" "${RELLOGS[@]}" || true
else
    echo "⏭️ Keine zusätzlichen Systemlogs gefunden"
fi

shopt -u nullglob

# ------------------------------------------------------------
# 4. STARFACE Modul-Logs
# ------------------------------------------------------------

echo
echo "=== 4. STARFACE Modul-Logs ==="

MODULEDIR="/var/starface/module/instances/repo"

if [[ -d "$MODULEDIR" ]]; then

    MODULEFILES=()

    while IFS= read -r -d '' file; do
        MODULEFILES+=("${file#/}")
    done < <(
        find "$MODULEDIR" \
            -type f \
            -path "*/log/log.log" \
            -print0 2>/dev/null
    )

    MODULE_COUNT=${#MODULEFILES[@]}

    echo "Gefundene Modul-Logs: $MODULE_COUNT"

    if (( MODULE_COUNT > 0 )); then

        # Dateien in Batches archivieren, um die
        # maximale Argumentlänge nicht zu überschreiten.

        BATCH_SIZE=100
        TOTAL=${#MODULEFILES[@]}

        for (( i=0; i<TOTAL; i+=BATCH_SIZE )); do

            BATCH=(
                "${MODULEFILES[@]:i:BATCH_SIZE}"
            )

            echo "📦 Modul-Logs: $((i + 1)) bis $((i + ${#BATCH[@]})) von $TOTAL"

            zip_add "Modul-Log-Batch" "${BATCH[@]}" || true
        done
    fi
else
    echo "⏭️ Modulverzeichnis nicht vorhanden"
fi

# ------------------------------------------------------------
# 5. Systeminformationen erfassen
# ------------------------------------------------------------

echo
echo "=== 5. Systeminformationen ==="

SYSINFO="$WORKDIR/systeminfo.txt"

{
    echo "### Hostname"
    hostname
    echo

    echo "### IP-Adressen"
    ip a
    echo

    echo "### Externe IP"
    curl -fsS \
        --connect-timeout 3 \
        --max-time 5 \
        https://api.ipify.org \
        || echo "Nicht verfügbar"
    echo

    echo "### Festplattennutzung"
    df -h
    echo

    echo "### Inodes"
    df -i
    echo

    echo "### RAM"
    free -h
    echo

    echo "### Load"
    uptime
    echo

    echo "### Prozesse"
    ps aux
    echo

    echo "### Java-Prozesse"
    pgrep -a java || echo "Keine gefunden"
    echo

    echo "### Routing"
    ip r
    echo

    echo "### DNS"

    if systemctl is-active --quiet systemd-resolved; then
        resolvectl status
    else
        cat /etc/resolv.conf
    fi
    echo

    echo "### Zeit"
    timedatectl
    echo

    echo "### chronyc"
    chronyc tracking 2>/dev/null \
        || echo "Nicht verfügbar"
    echo

    echo "### Top CPU-Prozesse"
    ps -eo pid,ppid,cmd,%mem,%cpu \
        --sort=-%cpu | head -n 15
    echo

    echo "### Fehlerhafte Dienste"
    systemctl list-units \
        --type=service \
        --state=failed
    echo

    echo "### Offene Ports"
    ss -tulpen
    echo

    echo "### Änderungen in /etc"
    find /etc \
        -type f \
        -printf "%T@ %Tc %p\n" \
        2>/dev/null | sort -n | tail -n 20
    echo

} > "$SYSINFO" 2>&1

echo "✅ Systeminformationen erfasst"

# ------------------------------------------------------------
# 6. Asterisk-Informationen
# ------------------------------------------------------------

echo
echo "=== 6. Asterisk-Informationen ==="

ASTERISKINFO="$WORKDIR/asteriskinfo.txt"

ASTERISK_COMMANDS=(
    "core show sysinfo"
    "core show uptime"
    "core show threads"
    "core show hints"
    "core show channels"
)

{
    for command in "${ASTERISK_COMMANDS[@]}"; do

        echo "### Asterisk: $command"

        timeout 15 rasterisk -x "$command" \
            || echo "Befehl fehlgeschlagen oder Timeout"

        echo
    done

} > "$ASTERISKINFO" 2>&1

echo "✅ Asterisk-Informationen erfasst"

# ------------------------------------------------------------
# 7. Datei- und Speicherinformationen
# ------------------------------------------------------------

echo
echo "=== 7. Speicherinformationen ==="

FILEINFO="$WORKDIR/files.txt"

{
    echo "### Fax-Verzeichnis"
    FAXDIR="/var/spool/asterisk/fax"

    if [[ -d "$FAXDIR" ]]; then
        du -sh "$FAXDIR" 2>/dev/null

        find "$FAXDIR" -type f \
            -exec du -h {} + 2>/dev/null \
            | sort -hr | head -n 20
    else
        echo "Nicht vorhanden"
    fi

    echo

    echo "### Voicemail-Verzeichnis"
    VOICEMAILDIR="/var/spool/asterisk/voicemail"

    if [[ -d "$VOICEMAILDIR" ]]; then
        du -sh "$VOICEMAILDIR" 2>/dev/null

        find "$VOICEMAILDIR" -type f \
            -exec du -h {} + 2>/dev/null \
            | sort -hr | head -n 20
    else
        echo "Nicht vorhanden"
    fi

    echo

    echo "### STARFACE Backups"
    BACKUPDIR="/home/starface/backup/Default"

    if [[ -d "$BACKUPDIR" ]]; then
        du -sh "$BACKUPDIR" 2>/dev/null

        find "$BACKUPDIR" \
            -maxdepth 1 \
            -type f \
            -name '*.sar' \
            -exec ls -lh {} + 2>/dev/null
    else
        echo "Nicht vorhanden"
    fi

} > "$FILEINFO" 2>&1

echo "✅ Speicherinformationen erfasst"

# ------------------------------------------------------------
# 8. Diagnoseinformationen ins ZIP aufnehmen
# ------------------------------------------------------------

echo
echo "=== 8. Diagnoseberichte archivieren ==="

if ! zip -q "-${ZIP_LEVEL}" -j "$ZIPPFAD" \
    "$SYSINFO" \
    "$ASTERISKINFO" \
    "$FILEINFO" \
    2>>"$ZIP_ERRORS"; then

    echo "⚠️ Diagnoseberichte konnten nicht vollständig archiviert werden"
    ZIP_FAILED=1
else
    echo "✅ Diagnoseberichte hinzugefügt"
fi

# ------------------------------------------------------------
# 9. Archiv prüfen
# ------------------------------------------------------------

echo
echo "=== 9. Archivprüfung ==="

if [[ ! -s "$ZIPPFAD" ]]; then
    echo "❌ ZIP-Archiv wurde nicht erstellt"
    exit 1
fi

echo "Prüfe ZIP-Struktur..."

if unzip -tq "$ZIPPFAD" >/dev/null 2>&1; then
    echo "✅ ZIP-Archiv ist lesbar"
else
    echo "❌ ZIP-Archivprüfung fehlgeschlagen"
    ZIP_FAILED=1
fi

# ------------------------------------------------------------
# 10. Ergebnis
# ------------------------------------------------------------

ENDE=$(date +%s)
DAUER=$((ENDE - START))

STUNDEN=$((DAUER / 3600))
MINUTEN=$(((DAUER % 3600) / 60))
SEKUNDEN=$((DAUER % 60))

echo
echo "============================================================"
echo "STARFACE LOG COLLECTOR - ERGEBNIS"
echo "============================================================"

echo "Archiv: $ZIPPFAD"
echo "Größe:  $(du -h "$ZIPPFAD" | cut -f1)"
printf 'Laufzeit: %02d:%02d:%02d\n' \
    "$STUNDEN" "$MINUTEN" "$SEKUNDEN"

echo

if (( ZIP_FAILED == 0 )); then
    echo "✅ Archivierung erfolgreich abgeschlossen"
else
    echo "⚠️ Archivierung mit Fehlern abgeschlossen"

    if [[ -s "$ZIP_ERRORS" ]]; then
        echo "Fehlerdetails:"
        cat "$ZIP_ERRORS"
    fi
fi

echo
echo "Entpacken mit:"
echo
echo "mkdir -p \"$ENTPACKPFAD\" && unzip \"$ZIPPFAD\" -d \"$ENTPACKPFAD\""

echo
echo "============================================================"

# ------------------------------------------------------------
# 11. Selbstlöschung
# ------------------------------------------------------------

# Nur Skripte löschen, die direkt aus /tmp gestartet wurden.
# Symbolische Links werden nicht verfolgt.

if [[ "$0" == /tmp/* && -f "$0" && ! -L "$0" ]]; then
    echo "🧹 Entferne temporäres Skript: $0"
    rm -f -- "$0"
fi

if (( ZIP_FAILED != 0 )); then
    exit 1
fi

exit 0
