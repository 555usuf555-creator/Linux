#!/bin/bash
# Сборка файлов для публичного репозитория.
# Скрипты копируются ОТСЮДА, с работающей машины, - чтобы в репозитории
# лежало ровно то, что было проверено в статьях.
set -u
DEST=/tmp/repo-export
rm -rf "$DEST"; mkdir -p "$DEST"/{monagent/tls,backup,tools}

echo "########## monagent ##########"
cp /opt/monagent/monagent.py            "$DEST/monagent/" 2>&1 && echo "ok monagent.py"
cp /opt/monagent/tls/server.crt         "$DEST/monagent/tls/" 2>&1 && echo "ok server.crt (тестовый)"
cp /etc/systemd/system/monagent.service "$DEST/monagent/" && echo "ok monagent.service"
cp /etc/logrotate.d/monagent            "$DEST/monagent/logrotate" 2>/dev/null && echo "ok logrotate"
cp /etc/sudoers.d/zz-usuf              "$DEST/" 2>/dev/null && echo "ok sudoers (справка)"
echo

echo "########## backup ##########"
cp /usr/local/sbin/appdata-backup.sh  "$DEST/backup/" && echo "ok appdata-backup.sh"
cp /usr/local/sbin/appdata-verify.sh  "$DEST/backup/" && echo "ok appdata-verify.sh"
cp /etc/systemd/system/appdata-backup.service  "$DEST/backup/" && echo "ok appdata-backup.service"
cp /etc/systemd/system/appdata-verify.service  "$DEST/backup/" && echo "ok appdata-verify.service"
cp /etc/systemd/system/appdata-backup.timer    "$DEST/backup/" && echo "ok appdata-backup.timer"
echo

echo "########## проверочные скрипты из статей ##########"
cp /tmp/guest.sh "$DEST/tools/last-run.sh" 2>/dev/null && echo "ok last-run.sh"
echo

echo "########## что получилось ##########"
find "$DEST" -type f | sed "s|$DEST/||" | sort | while read f; do
  printf '  %-42s %6s байт\n' "$f" "$(stat -c%s "$DEST/$f")"
done
echo
echo "файлов: $(find "$DEST" -type f | wc -l)"
echo
echo "########## публичный ключ мониторинга для проверки ##########"
# публичный ключ - это не секрет, его можно показать
cat /home/usuf/.ssh/authorized_keys 2>/dev/null | grep -v '^#' || echo "(нет)"
