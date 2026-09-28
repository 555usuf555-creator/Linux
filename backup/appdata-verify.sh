#!/bin/bash
# ВОССТАНАВЛИВАЕТ данные в отдельный каталог и проверяет, что они
# целы. Бэкап без такой проверки - это надежда, а не бэкап.
set -u
DATA=/srv/appdata
BACKUP=/backup/appdata
RESTORE=/restore-test
OK=0
FAIL=0

say() { echo "  $1"; }
check() {
  if [ "$1" = "0" ]; then say "OK    $2"; OK=$((OK+1));
  else say "СБОЙ  $2"; FAIL=$((FAIL+1)); fi
}

SNAP=$(ls -1d "$BACKUP"/2* 2>/dev/null | sort | tail -1)
if [ -z "$SNAP" ]; then echo "СНАПШОТОВ НЕТ - проверять нечего"; exit 2; fi

echo "СНАПШОТ: $SNAP"
echo

rm -rf "$RESTORE"; mkdir -p "$RESTORE"

echo "1. ЦЕЛОСТНОСТЬ КАЖДОГО ФАЙЛА (сравнение с оригиналом)"
( cd "$SNAP" && find . -type f | sort | xargs md5sum ) > /tmp/snap.md5
( cd "$DATA"  && find . -type f | sort | xargs md5sum ) > /tmp/live.md5
if diff -q /tmp/snap.md5 /tmp/live.md5 >/dev/null 2>&1; then
  check 0 "все $(wc -l < /tmp/snap.md5) файлов совпадают с оригиналом по md5"
else
  check 1 "файлы снапшота отличаются от текущих данных"
  diff /tmp/snap.md5 /tmp/live.md5 | head -5 | sed 's/^/      /'
fi
echo

echo "2. ВОССТАНОВЛЕНИЕ В ОТДЕЛЬНЫЙ КАТАЛОГ"
rsync -a "$SNAP"/ "$RESTORE"/ && check 0 "rsync отработал без ошибок" || check 1 "rsync вернул ошибку"
check $([ -f "$RESTORE/db/records.dat" ] && echo 0 || echo 1) "файл базы данных на месте после восстановления"
check $([ -f "$RESTORE/config/app.conf" ] && echo 0 || echo 1) "конфигурация приложения на месте"
check $([ -f "$RESTORE/uploads/blob-001.bin" ] && echo 0 || echo 1) "бинарный файл на месте"
echo

echo "3. ЧИТАЕМОСТЬ ВОССТАНОВЛЕННОГО (а не просто наличие)"
REC=$(wc -l < "$RESTORE/db/records.dat" 2>/dev/null || echo 0)
say "строк в восстановленной базе: $REC"
check $([ "$REC" -ge 4000 ] && echo 0 || echo 1) "база содержит не меньше 4000 строк"
USR=$(wc -l < "$RESTORE/db/users.csv" 2>/dev/null || echo 0)
check $([ "$USR" -ge 201 ] && echo 0 || echo 1) "CSV читается и содержит $USR строк"
if grep -q 'listen = 8443' "$RESTORE/config/app.conf" 2>/dev/null; then
  check 0 "конфиг читается и содержит ожидаемые значения"
else
  check 1 "конфиг не читается или значения потеряны"
fi
echo

echo "4. ПРАВА И ВЛАДЕЛЕЦЫ"
OWNER=$(stat -c '%U:%G' "$RESTORE/db/records.dat" 2>/dev/null || echo "нет")
say "владелец восстановленного файла: $OWNER"
check $([ "$OWNER" = "root:root" ] && echo 0 || echo 1) "владелец сохранился при копировании"
echo

echo "5. СВОБОДНОЕ МЕСТО (снапшоты не должны съесть диск)"
USE=$(df --output=pcent / | tail -1 | tr -dc '0-9')
say "диск занят на ${USE}%"
check $([ "$USE" -lt 80 ] && echo 0 || echo 1) "диск не переполнен"
echo

echo "ИТОГ: успешно $OK, провалено $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
