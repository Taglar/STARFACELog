#!/bin/bash

# Ziel-Dateiname mit Zeitstempel im gewünschten Verzeichnis
ZIPFILE="/tmp/logs_$(date +%Y-%m-%d_%H-%M).zip"

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

# ZIP erstellen
cd "$TMPDIR" || exit 1
zip -r "$ZIPFILE" . > /dev/null

# Aufräumen
cd /
rm -rf "$TMPDIR"

echo "✅ Archiv wurde erstellt unter: $ZIPFILE"
