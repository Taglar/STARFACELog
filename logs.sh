#!/bin/bash

# Setze Zielpfad
DATE=$(date +"%Y-%m-%d_%H-%M")
ZIPFILE="/tmp/logs_${DATE}.zip"
TMPDIR="/tmp/logs_${DATE}"

mkdir -p "$TMPDIR"

# 1. Logs sammeln
echo "[+] Sammle Log-Dateien..."

# Verzeichnisse
cp -r --parents /var/log/asterisk "$TMPDIR"
cp -r --parents /var/log/starface/openfire "$TMPDIR"
cp -r --parents /var/log/starface/postgresql "$TMPDIR"
cp -r --parents /var/starface/fs-interface "$TMPDIR"
cp -r --parents /var/spool/hylafax/log "$TMPDIR"
cp -r --parents /var/log/starface "$TMPDIR"  # GANZER STARFACE-LOGORDNER

# Einzeldateien inkl. Rotationen
find /var/log/starface/ -type f -name "messages*" -exec cp --parents {} "$TMPDIR" \;
find /var/log/starface/ -type f -name "maillog" -exec cp --parents {} "$TMPDIR" \;
find /var/log/starface/ -type f -name "kamailio.log*" -exec cp --parents {} "$TMPDIR" \;

# Modul-Logs
find /var/starface/module/instances/repo/ -type f -path "*/log/log.log" -exec cp --parents {} "$TMPDIR" \;

# 2. Systeminformationen sammeln
echo "[+] Sammle Systeminformationen..."
SYSINFO="$TMPDIR/systeminfo.txt"

{
  echo "Hostname: $(hostname)"
  echo
  echo "IP-Adressen:"
  ip a
  echo
  echo "Externe IP:"
  curl -s https://api.ipify.org
  echo
  echo "Festplatte:"
  df -h
  echo
  echo "RAM:"
  free -h
  echo
  echo "Inodes:"
  df -i
  echo
  echo "System Load:"
  uptime
  echo
  echo "Laufende Prozesse:"
  ps auxf
  echo
  echo "Laufende Java-Prozesse:"
  ps -eo pid,cmd | grep java | grep -v grep
} > "$SYSINFO"

# 3. ZIP erstellen
echo "[+] Erstelle Archiv $ZIPFILE..."
cd "$TMPDIR"/..
zip -r "$ZIPFILE" "$(basename "$TMPDIR")" >/dev/null

# 4. Aufräumen
rm -rf "$TMPDIR"

# 5. Hinweis zum Entpacken
echo
echo "[✓] Log-Archiv wurde erstellt: $ZIPFILE"
echo "Zum Entpacken verwende z. B.:"
echo "unzip $ZIPFILE -d \"${ZIPFILE%.zip}\""
echo

# 6. Skript selbst löschen
echo "[*] Entferne mich selbst: $0"
rm -- "$0"
