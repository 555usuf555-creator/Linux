#!/bin/bash
# Деплой с проверкой здоровья и автоматическим откатом.
set -u
ROOT=/opt/deploylab
CURRENT=$ROOT/current
PREVIOUS=$ROOT/previous
LOG=$ROOT/deploy.log
PORT=8099
URL="http://127.0.0.1:$PORT/healthz"
ATTEMPTS=6
INTERVAL=1

log() { printf '%s  %s\n' "$(date '+%F %T')" "$1" | tee -a "$LOG"; }

if [ $# -ne 1 ]; then
  echo "использование: deploy.sh <каталог-версии>" >&2
  exit 2
fi
TARGET="$(readlink -f "$1")"

[ -f "$TARGET/app.py" ] || { log "ОТКАЗ: в $1 нет app.py"; exit 2; }

WAS=""
[ -L "$CURRENT" ] && WAS="$(readlink -f "$CURRENT")"
if [ -n "$WAS" ] && [ "$WAS" != "$TARGET" ]; then
  ln -sfn "$WAS" "$PREVIOUS"
  log "запомнил для отката: $(basename "$WAS")"
fi

ln -sfn "$TARGET" "$CURRENT"
log "переключил current -> $(basename "$TARGET")"
systemctl restart deploylab-app.service
log "служба перезапущена"

OK=0
for i in $(seq 1 "$ATTEMPTS"); do
  sleep "$INTERVAL"
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL" 2>/dev/null)
  if [ "$CODE" = "200" ]; then
    log "проверка $i/$ATTEMPTS: HTTP $CODE - здорово"
    OK=1
    break
  fi
  log "проверка $i/$ATTEMPTS: HTTP ${CODE:-нет ответа}"
done

if [ "$OK" = "1" ]; then
  printf '%s\n' "$(basename "$TARGET")" > "$ROOT/state/known_good"
  log "ПРИНЯТО: версия $(basename "$TARGET") работает"
  exit 0
fi

log "ОТКАТ: версия $(basename "$TARGET") не прошла проверку (попыток: $ATTEMPTS)"

if [ -L "$PREVIOUS" ]; then
  ln -sfn "$(readlink -f "$PREVIOUS")" "$CURRENT"
  systemctl restart deploylab-app.service
  sleep 2
  RCODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL" 2>/dev/null)
  log "откат на $(basename "$(readlink -f "$CURRENT")"), проверка: HTTP ${RCODE:-нет ответа}"
  [ "$RCODE" = "200" ] && log "ОТКАТ УСПЕШЕН, сервис снова в работе" \
                      || log "ВНИМАНИЕ: после отката тоже не отвечает, разбираться руками"
else
  log "откатить не на что: предыдущей версии нет (это первый деплой)"
fi
exit 1
