#!/bin/bash
# Установка системы бэкапа с проверкой восстановимости.
set -eu

DATA=/srv/appdata
BACKUP=/backup/appdata
KEEP_DAYS=7

say() { printf '\n=== %s ===\n' "$1"; }

[ "$(id -u)" -eq 0 ] || { echo "запускать от root: sudo ./install.sh"; exit 1; }
command -v rsync >/dev/null || { echo "нужен rsync"; exit 1; }

say "1. проверочный скрипт берём из системы и сразу чиним известный дефект"
install -m 755 appdata-backup.sh /usr/local/sbin/appdata-backup.sh
install -m 755 appdata-verify.sh /usr/local/sbin/appdata-verify.sh
echo "установлено в /usr/local/sbin/"

say "2. каталоги"
install -d -m 700 "$BACKUP"
[ -d "$DATA" ] || install -d -m 700 "$DATA"
echo "данные:  $DATA"
echo "бэкапы:  $BACKUP"

say "3. unit-файлы"
install -m 644 appdata-backup.service /etc/systemd/system/appdata-backup.service
install -m 644 appdata-verify.service /etc/systemd/system/appdata-verify.service
install -m 644 appdata-backup.timer   /etc/systemd/system/appdata-backup.timer
systemctl daemon-reload

say "4. включаем таймер"
# ВАЖНО: enable только создаёт symlink, но не запускает таймер.
# Без отдельного start он останется неактивным.
systemctl enable appdata-backup.timer
systemctl start  appdata-backup.timer
echo "состояние: $(systemctl is-active appdata-backup.timer)"
systemctl list-timers appdata-backup.timer --no-pager | tail -2

say "5. первый снапшот и проверка"
/usr/local/sbin/appdata-backup.sh
/usr/local/sbin/appdata-verify.sh && echo "проверка пройдена" || echo "ВНИМАНИЕ: проверка не прошла"

say "6. главное: убедиться, что проверка вообще ловит порчу"
echo "Сейчас испортим снапшот и убедимся, что проверка упадёт."
SNAP=$(ls -1d "$BACKUP"/2* 2>/dev/null | sort | tail -1)
if [ -n "$SNAP" ] && [ -f "$SNAP/db/records.dat" ]; then
  dd if=/dev/zero of="$SNAP/db/records.dat" bs=1024 count=20 conv=notrunc 2>/dev/null
  echo "снапшот испорчен: $SNAP/db/records.dat"
  if /usr/local/sbin/appdata-verify.sh; then
    echo "ОШИБКА: проверка прошла на испорченных данных. Так бывает, если проверка"
    echo "ничего не делает. Это хуже, чем отсутствие проверки."
  else
    echo "верно: проверка упала на испорченных данных"
    echo "создаём новый снапшот, чтобы вернуть систему в рабочее состояние"
    /usr/local/sbin/appdata-backup.sh
    /usr/local/sbin/appdata-verify.sh && echo "восстановлено"
  fi
else
  echo "пропускаем проверку порчи: нет файла db/records.dat в снапшоте"
  echo "(он создаётся демо-данными из article, на своём каталоге данных замените путь)"
fi

cat <<'MSG'

Готово. Бэкап запускается в 03:15 ежедневно, проверка - сразу после него.

Посмотреть расписание:
  systemctl list-timers appdata-backup.timer
  journalctl -u appdata-backup -n 40

Проверить вручную прямо сейчас:
  sudo /usr/local/sbin/appdata-verify.sh

Убрать:
  systemctl disable --now appdata-backup.timer
  rm /etc/systemd/system/appdata-backup.*
  rm /etc/systemd/system/appdata-verify.*
  rm /usr/local/sbin/appdata-*
MSG
