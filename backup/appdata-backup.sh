#!/bin/bash
# Бэкап с ежедневными снапшотами. Прежние не удаляются - поэтому
# --link-dest вместо --delete: старый снимок остаётся нетронутым,
# а новый занимает только изменившиеся файлы.
set -eu
DATA=/srv/appdata
BACKUP=/backup/appdata
KEEP_DAYS=7

STAMP=$(date +%Y%m%d-%H%M%S)-$$
# если каталог уже есть (коллизия в одну секунду), добавляем счётчик
[ -d "$BACKUP/$STAMP" ] && STAMP="$STAMP-$RANDOM"
DEST="$BACKUP/$STAMP"
PREV=$(ls -1d "$BACKUP"/2* 2>/dev/null | sort | tail -1 || true)

mkdir -p "$DEST"

LINKARG=()
if [ -n "$PREV" ]; then
  LINKARG=(--link-dest="$PREV")
  echo "база для инкрементного снапшота: $PREV"
fi

rsync -a --delete "${LINKARG[@]}" "$DATA"/ "$DEST"/

# ротация: старые снимки удаляем, свежие храним
find "$BACKUP" -maxdepth 1 -type d -name '2*' -mtime "+$KEEP_DAYS" -exec rm -rf {} + 2>/dev/null || true

echo "снапшот создан: $DEST"
du -sh "$DEST" | awk '{print "  размер снапшота: "$1}'
