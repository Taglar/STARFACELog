#!/bin/bash

# Ziel-Dateiname mit Zeitstempel im gewünschten Verzeichnis
ZIPFILE="/tmp/logs_$(date +%Y-%m-%d_%H-%M).zip"
ZIPNAME=$(basename "$ZIPFILE")
UNZIP_DIR="${ZIPFILE%.zip}"

# Temporäres Arbeitsverzeichnis
TMPDIR=$(mktemp -d)

echo "📁 Sammle Dateien in $TMPDIR ..."

# 1. Kompletter Ordner /var/log/asterisk/
cp -r --parents /var/log/asterisk "$TMPDIR"

# 2. /var/log/messages*
cp --parents /var/log/messages* "$TMPDIR" 2>/dev/null

# 3. /var/log/maillog
cp --parents /var/log/maillog "$TMPDIR" 2>/dev/null

# 4. /var/log/kamailio.log*
cp --parents /var/log/kamailio.log* "$TMPDIR" 2>/dev/null

# 5. Ordner openfire (direkt in /var/log/)
cp -r --parents /var/log/openfire "$TMPDIR"

# 6. Ordner postgresql (direkt in /var/log/)
cp -r --parents /var/log/postgresql "$TMPDIR"

# 7. Alle log.log aus repo/*/log/
for file in /var/starface/module/instances/repo/*/log/log.log; do
  if [[ -f "$file" ]]; then
    cp --parents "$file" "$TMPDIR"
  fi
done

# 8. fs-interface Ordner
cp -r --parents /var/starface/fs-interface "$TMPDIR"

# 9. Hylafax log Ordner
cp -r --parents /var/spool/hylafax/log "$TMPDIR"

# 10. Systeminfo erfassen
SYSINFO="$TMPDIR/systeminfo.txt"

{
  echo "### Hostname"
  hostname
  echo

  echo "### IP-Adressen (ip a)"
  ip a
  echo

  echo "### Externe IP-Adresse"
  curl -s ifconfig.me || echo "Nicht ermittelbar"
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
  ps aux | grep [j]ava || echo "Keine Java-Prozesse gefunden"
  echo

} > "$SYSINFO"

# Weitere Support-Dateien

# IP-Routen
ip r > "$TMPDIR/ip_routes.txt"

# DNS-Status
if command -v resolvectl &>/dev/null && resolvectl status &>/dev/null; then
  resolvectl status > "$TMPDIR/dns_status.txt"
else
  echo "resolvectl nicht verfügbar – Fallback auf /etc/resolv.conf" > "$TMPDIR/dns_status.txt"
  cat /etc/resolv.conf >> "$TMPDIR/dns_status.txt"
fi

# NTP/Zeit
{
  echo "### timedatectl"
  timedatectl
  echo
  echo "### chronyc tracking"
  chronyc tracking 2>/dev/null || echo "chronyc nicht verfügbar"
} > "$TMPDIR/ntp_status.txt"

# Top CPU/RAM Prozesse
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 15 > "$TMPDIR/top_processes.txt"

# Services mit Fehlerstatus
systemctl list-units --type=service --state=failed > "$TMPDIR/services_failed.txt"

# Offene Ports
ss -tulpen > "$TMPDIR/ports.txt"

# Geänderte Dateien unter /etc
find /etc -type f -printf "%T@ %Tc %p\n" 2>/dev/null | sort -n | tail -n 20 > "$TMPDIR/recent_changes_etc.txt"

# ZIP erstellen
cd "$TMPDIR" || exit 1
zip -r "$ZIPFILE" . > /dev/null

# Aufräumen
cd /
rm -rf "$TMPDIR"

# Abschlussmeldung
echo "✅ Archiv wurde erstellt: $ZIPFILE"
echo ""
echo "📦 Du kannst das Archiv mit folgendem Befehl entpacken:"
echo "unzip $ZIPFILE -d \"$UNZIP_DIR\""

# Script selbst löschen (wenn direkt aufgerufen, nicht gesourced)
if [[ "$0" == /*tmp/* && -f "$0" ]]; then
  echo "🧹 Lösche das Skript selbst: $0"
  rm -- "$0"
fi
