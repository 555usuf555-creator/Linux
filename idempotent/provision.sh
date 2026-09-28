#!/bin/bash
# Идемпотентный скрипт настройки.
# Правило: запусти хоть сто раз - система должна остаться такой же.
# Значит на каждом шаге сначала СПРАШИВАЕМ, и только потом меняем.
set -u
T=/opt/idemlab
CHANGES=0

changed() { echo "  ИЗМЕНЕНО: $1"; CHANGES=$((CHANGES + 1)); }
same()    { echo "  без изменений: $1"; }

# --- 1. пользователь: создать, только если нет ---
if id -u service-app >/dev/null 2>&1; then
  same "пользователь service-app уже есть"
else
  useradd --system --no-create-home --shell /sbin/nologin service-app
  changed "создан пользователь service-app"
fi

# --- 2. параметры в конфиге: дописывать, только если значения нет ---
add_line() {
  # $1 - файл, $2 - строка
  if grep -qxF "$2" "$1" 2>/dev/null; then
    same "уже есть: $2"
  else
    printf '%s\n' "$2" >> "$1"
    changed "дописано в $(basename "$1"): $2"
  fi
}
add_line "$T/target/app.conf" 'admin_email = ops@example.local'
add_line "$T/target/app.conf" 'log_level = info'

# --- 3. хост в списке: тот же принцип ---
add_line /var/lib/idemlab/hosts.conf '10.0.0.5'

# --- 4. права: ТОЛЬКО если они неправильные ---
# chmod идемпотентен сам по себе, но проверка даёт
# внятный отчёт и не трогает файл зря
CUR=$(stat -c '%a' "$T/target/app.conf" 2>/dev/null)
if [ "$CUR" = "640" ]; then
  same "права на app.conf уже 640"
else
  chmod 640 "$T/target/app.conf"
  changed "права app.conf: ${CUR:-нет} -> 640"
fi

# --- 5. каталог: mkdir -p не падает, если каталог есть ---
mkdir -p "$T/target/cache" && same "каталог cache на месте"

# --- 6. вывод: сколько реально изменилось ---
if [ "$CHANGES" -eq 0 ]; then
  echo "ИТОГ: изменений нет. Система уже в нужном состоянии."
else
  echo "ИТОГ: изменений $CHANGES."
fi
