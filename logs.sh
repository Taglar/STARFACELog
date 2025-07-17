#!/bin/bash

# Zeitstempel & Pfade
DATUM=$(date '+%Y-%m-%d_%H-%M-%S')
ZIPNAME="logs_${DATUM}.zip"
TMPDIR="/tmp/logs_${DATUM}"
ZIPPFAD="/tmp/${ZIPNAME}"
ENTPACKPFAD="/tmp/SFLogs/${DATUM}"

echo "📁 Erstelle temporäres Verzeichnis: $TMPDIR"
mkdir -p "$TMPDIR"

# Verzeichnisstruktur vorbereiten
echo "📁 Erstelle Zielverzeichnisse..."
mkdir -p "$TMPDIR/var/log/asterisk"
mkdir -p "$TMPDIR/var/log/starface"
mkdir -p "$TMPDIR/var/starface/fs-interface"
mkdir -p "$TMPDIR/var/spool/hylafax/log"
mkdir -p "$TMPDIR/var/log/openfire"
mkdir -p "$TMPDIR/var/log/postgresql"

# 1. Komplette Verzeichnisse kopieren
echo "📥 Kopiere vollständige Verzeichnisse..."
rsync -a /var/log/asterisk/ "$TMPDIR/var/log/asterisk/" 2>/dev/null
rsync -a /var/log/tomcat/ "$TMPDIR/var/log/tomcat/" 2>/dev/null
rsync -a /var/log/starface/ "$TMPDIR/var/log/starface/" 2>/dev/null
rsync -a /var/starface/fs-interface/ "$TMPDIR/var/starface/fs-interface/" 2>/dev/null
rsync -a /var/spool/hylafax/log/ "$TMPDIR/var/spool/hylafax/log/" 2>/dev/null

# 2. Symlinks folgen für openfire/postgresql
echo "🔗 Kopiere openfire/postgresql falls vorhanden..."
[[ -d /var/log/openfire ]] && rsync -Lra /var/log/openfire/ "$TMPDIR/var/log/openfire/"
[[ -d /var/log/postgresql ]] && rsync -Lra /var/log/postgresql/ "$TMPDIR/var/log/postgresql/"

# 3. Einzeldateien aus /var/log/
echo "📥 Kopiere messages*, maillog, kamailio.log*..."
cp -a /var/log/messages* "$TMPDIR/var/log/" 2>/dev/null
cp -a /var/log/maillog "$TMPDIR/var/log/" 2>/dev/null
cp -a /var/log/kamailio.log* "$TMPDIR/var/log/" 2>/dev/null

# 4. Modul-Logdateien sammeln (log.log aus Modulen)
echo "🔍 Sammle log.log aus Modulen..."
find /var/starface/module/instances/repo/ -type f -path "*/log/log.log" -exec bash -c '
  for filepath; do
    relpath="${filepath#/}"
    mkdir -p "'$TMPDIR'/$(dirname "$relpath")"
    cp -a "$filepath" "'$TMPDIR'/$relpath"
  done
' bash {} +

# 5. Systeminformationen erfassen
echo "🧠 Erfasse Systeminformationen..."
SYSINFO="${TMPDIR}/systeminfo.txt"
{
  echo "### Hostname"; hostname; echo
  echo "### IP-Adressen"; ip a; echo
  echo "### Externe IP"; curl -s https://api.ipify.org || echo "Fehler beim Abruf"; echo
  echo "### Festplattennutzung"; df -h; echo
  echo "### Inodes"; df -i; echo
  echo "### RAM"; free -h; echo
  echo "### Load"; uptime; echo
  echo "### Prozesse"; ps aux; echo
  echo "### Java-Prozesse"; pgrep -a java || echo "Keine gefunden"; echo
  echo "### Routing"; ip r; echo
  echo "### DNS"; systemctl is-active systemd-resolved && resolvectl status || cat /etc/resolv.conf; echo
  echo "### Zeit"; timedatectl; echo
  echo "### chronyc"; chronyc tracking 2>/dev/null || echo "Nicht verfügbar"; echo
  echo "### Top CPU-Prozesse"; ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 15; echo
  echo "### Fehlerhafte Dienste"; systemctl list-units --type=service --state=failed || echo "Keine"; echo
  echo "### Offene Ports"; ss -tulpen; echo
  echo "### Änderungen in /etc"; find /etc -type f -printf "%T@ %Tc %p\n" 2>/dev/null | sort -n | tail -n 20; echo
} > "$SYSINFO"

# 6. Asteriskinfos erfassen
ASTERISKINFO="${TMPDIR}/asteriskinfo.txt"
{
  echo "### Asterisk core show sysinfo"; rasterisk -x 'core show sysinfo'; echo
  echo "### Asterisk core show uptime"; rasterisk -x 'core show uptime'; echo
  echo "### Asterisk core show threads"; rasterisk -x 'core show threads'; echo
  echo "### Asterisk core show hints"; rasterisk -x 'core show hints'; echo
  echo "### Asterisk core show channels"; rasterisk -x 'core show channels'; echo
} > "$ASTERISKINFO"

# 7. Dateien und Größen prüfen
FILEINFO="${TMPDIR}/files.txt"
{
  echo "### 📂 Fax-Verzeichnis: /var/spool/asterisk/fax"
  du -sh /var/spool/asterisk/fax 2>/dev/null || echo "Nicht vorhanden"
  find /var/spool/asterisk/fax -type f -exec du -h {} + 2>/dev/null | sort -hr | head -n 20 || true
  echo

  echo "### 📂 Voicemail-Verzeichnis: /var/spool/asterisk/voicemail"
  du -sh /var/spool/asterisk/voicemail 2>/dev/null || echo "Nicht vorhanden"
  find /var/spool/asterisk/voicemail -type f -exec du -h {} + 2>/dev/null | sort -hr | head -n 20 || true
  echo

  echo "### 📂 Backups: /home/starface/backup/Default/"
  du -sh /home/starface/backup/Default 2>/dev/null || echo "Nicht vorhanden"
  ls -lh /home/starface/backup/Default/*.sar 2>/dev/null || echo "Keine .sar-Dateien gefunden"
} > "$FILEINFO"

# 8. ZIP erstellen (nur Inhalte, kein doppelter Ordner)
echo "📦 Erstelle ZIP: $ZIPPFAD"
cd "$TMPDIR"
zip -r "$ZIPPFAD" . >/dev/null

# 9. Aufräumen
rm -rf "$TMPDIR"

# 10. Entpackhilfe anzeigen
echo
echo "✅ Archiv erstellt: $ZIPPFAD"
echo "################################################################################"
echo "📂 Entpacken mit:"
echo "mkdir -p \"$ENTPACKPFAD\" && unzip \"$ZIPPFAD\" -d \"$ENTPACKPFAD\""
echo "################################################################################"
echo

# 11. Selbstlöschung
if [[ "$0" == /tmp/* && -f "$0" ]]; then
  echo "🧹 Lösche mich selbst: $0"
  rm -f "$0"
fi
