#!/bin/bash

# Zielverzeichnis für ZIP-Datei
DATUM=$(date '+%Y-%m-%d_%H-%M')
ZIPNAME="logs_${DATUM}.zip"
TMPDIR="/tmp/logs_${DATUM}"
ZIPPFAD="/tmp/${ZIPNAME}"

# Temporäres Verzeichnis vorbereiten
mkdir -p "$TMPDIR"

echo "📁 Sammle Logdateien..."

# 1. Komplette Verzeichnisse kopieren
rsync -a /var/log/asterisk/ "$TMPDIR/var/log/asterisk/"
rsync -a /var/log/starface/ "$TMPDIR/var/log/starface/"
rsync -a /var/starface/fs-interface/ "$TMPDIR/var/starface/fs-interface/"
rsync -a /var/spool/hylafax/log/ "$TMPDIR/var/spool/hylafax/log/"

# 2. Symlinks für openfire und postgresql folgen (wenn vorhanden)
[[ -d /var/log/openfire ]] && rsync -Lra /var/log/openfire/ "$TMPDIR/var/log/openfire/"
[[ -d /var/log/postgresql ]] && rsync -Lra /var/log/postgresql/ "$TMPDIR/var/log/postgresql/"

# 3. Einzelne Logdateien aus /var/log/
mkdir -p "$TMPDIR/var/log"
cp -a /var/log/messages* "$TMPDIR/var/log/" 2>/dev/null
cp -a /var/log/maillog "$TMPDIR/var/log/" 2>/dev/null
cp -a /var/log/kamailio.log* "$TMPDIR/var/log/" 2>/dev/null

# 4. Modul-Logdateien (log.log aus jedem Modulpfad)
find /var/starface/module/instances/repo/ -type f -path "*/log/log.log" -exec bash -c '
  for filepath; do
    relpath="${filepath#/}"
    mkdir -p "'$TMPDIR'/$(dirname "$relpath")"
    cp -a "$filepath" "'$TMPDIR'/$relpath"
  done
' bash {} +

# 5. Systeminformationen erfassen
SYSINFO="${TMPDIR}/systeminfo.txt"
echo "🧠 Erfasse Systeminformationen..."
{
  echo "### Hostname"
  hostname
  echo

  echo "### IP-Adressen (ip a)"
  ip a
  echo

  echo "### Externe IP-Adresse"
  curl -s https://api.ipify.org || echo "Fehler beim Abruf"
  echo

  echo "### Festplattennutzung"
  df -h
  echo

  echo "### Inodes"
  df -i
  echo

  echo "### RAM + Swap"
  free -h
  echo

  echo "### Systemlast"
  uptime
  echo

  echo "### Laufende Prozesse"
  ps aux
  echo

  echo "### Laufende Java-Prozesse"
  pgrep -a java || echo "Keine Java-Prozesse gefunden"
  echo

  echo "### Routing-Tabelle"
  ip r
  echo

  echo "### DNS-Status"
  if systemctl is-active --quiet systemd-resolved.service; then
    resolvectl status
  else
    echo "systemd-resolved nicht aktiv – zeige /etc/resolv.conf"
    cat /etc/resolv.conf
  fi
  echo

  echo "### Zeitstatus"
  timedatectl
  echo
  echo "### chronyc tracking"
  chronyc tracking 2>/dev/null || echo "chronyc nicht verfügbar"
  echo

  echo "### Top-Prozesse nach CPU"
  ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 15
  echo

  echo "### Fehlgeschlagene Services"
  systemctl list-units --type=service --state=failed || echo "Keine fehlgeschlagenen Services"
  echo

  echo "### Offene Ports"
  ss -tulpen
  echo

  echo "### Letzte Änderungen in /etc"
  find /etc -type f -printf "%T@ %Tc %p\n" 2>/dev/null | sort -n | tail -n 20
  echo

} > "$SYSINFO"

# 6. Archiv erstellen
echo "📦 Erstelle ZIP: $ZIPPFAD"
cd "$TMPDIR/.." || exit 1
zip -r "$ZIPPFAD" "$(basename "$TMPDIR")" >/dev/null

# 7. Aufräumen
rm -rf "$TMPDIR"

# 8. Abschlussmeldung
echo
echo "✅ Archiv erstellt unter: $ZIPPFAD"
echo "📂 Entpacken mit:"
echo "unzip $ZIPPFAD -d \"${ZIPPFAD%.zip}\""
echo

# 9. Selbstlöschung
if [[ "$0" == /tmp/* && -f "$0" ]]; then
  echo "🧹 Lösche Script selbst: $0"
  rm -f "$0"
fi
