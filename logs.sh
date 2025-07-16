#!/bin/bash

# Zielverzeichnis für ZIP-Datei
DATUM=$(date '+%Y-%m-%d_%H-%M')
ZIPNAME="logs_${DATUM}.zip"
TMPDIR="/tmp/logs_${DATUM}"
ZIPPFAD="/tmp/${ZIPNAME}"

# Verzeichnisse vorbereiten
mkdir -p "$TMPDIR"

echo "Sammle Logdaten..."

# Logs & Verzeichnisse sammeln
mkdir -p "$TMPDIR/var"

# Kopiere ganze Verzeichnisse (rekursiv & mit Pfad)
rsync -a /var/log/asterisk/ "$TMPDIR/var/log/asterisk/"
rsync -a /var/log/starface/ "$TMPDIR/var/log/starface/"
rsync -a /var/log/openfire/ "$TMPDIR/var/log/openfire/"
rsync -a /var/log/postgresql/ "$TMPDIR/var/log/postgresql/"
rsync -a /var/starface/fs-interface/ "$TMPDIR/var/starface/fs-interface/"
rsync -a /var/spool/hylafax/log/ "$TMPDIR/var/spool/hylafax/log/"

# Einzeldateien sammeln
mkdir -p "$TMPDIR/var/log/starface"
cp -a /var/log/starface/messages* "$TMPDIR/var/log/starface/" 2>/dev/null
cp -a /var/log/starface/maillog "$TMPDIR/var/log/starface/" 2>/dev/null
cp -a /var/log/starface/kamailio.log* "$TMPDIR/var/log/starface/" 2>/dev/null

# Modul-Logs sammeln
find /var/starface/module/instances/repo/ -type f -path "*/log/log.log" -exec bash -c '
  for filepath; do
    relpath="${filepath#/}"
    mkdir -p "'$TMPDIR'/$(dirname "$relpath")"
    cp -a "$filepath" "'$TMPDIR'/$relpath"
  done
' bash {} +

# Systeminformationen sammeln
SYSINFO="${TMPDIR}/systeminfo.txt"
{
  echo "Hostname: $(hostname)"
  echo
  echo "IP-Adressen:"
  ip a
  echo
  echo "Externe IP:"
  curl -s https://api.ipify.org || echo "Fehler beim Abruf"
  echo
  echo "Freier Speicher (Festplatte):"
  df -h /
  echo
  echo "Freier Speicher (Inodes):"
  df -ih /
  echo
  echo "Freier RAM:"
  free -h
  echo
  echo "System Load:"
  uptime
  echo
  echo "Laufende Prozesse:"
  ps aux --sort=-%mem | head -n 30
  echo
  echo "Laufende Java-Prozesse:"
  pgrep -a java || echo "Keine Java-Prozesse gefunden"
} > "$SYSINFO"

# ZIP erstellen
echo "Erstelle ZIP-Datei: $ZIPPFAD"
cd "$TMPDIR/.." || exit 1
zip -r "$ZIPPFAD" "$(basename "$TMPDIR")" >/dev/null

# Hinweis zum Entpacken
echo
echo "FERTIG: Logs wurden gepackt in:"
echo "  $ZIPPFAD"
echo
echo "Du kannst sie entpacken mit:"
echo "  unzip \"$ZIPPFAD\" -d \"/tmp/$(basename "$TMPDIR")\""
echo

# Aufräumen: Script selbst löschen
if [[ $0 == /tmp/* ]]; then
  echo "Entferne Script: $0"
  rm -f "$0"
fi
