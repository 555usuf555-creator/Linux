#!/bin/bash
# Установка агента мониторинга monagent.
# Всё, что здесь происходит, проверено на ALT Linux 10.4.
set -eu

PREFIX=/opt/monagent
HOST=127.0.0.1
PORT=8443
DAYS=825

say() { printf '\n=== %s ===\n' "$1"; }

[ "$(id -u)" -eq 0 ] || { echo "запускать от root: sudo ./install.sh"; exit 1; }
command -v python3 >/dev/null || { echo "нужен python3"; exit 1; }
command -v openssl >/dev/null || { echo "нужен openssl"; exit 1; }

say "1. каталог и скрипт"
install -d -m 755 "$PREFIX"
install -d -m 755 "$PREFIX/tls"
install -m 755 monagent.py "$PREFIX/monagent.py"
echo "поставлено: $PREFIX/monagent.py"

say "2. сертификат для TLS"
# -addext subjectAltName обязателен: без него клиент с проверкой
# отвергнет сертификат при подключении по IP
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$PREFIX/tls/server.key" -out "$PREFIX/tls/server.crt" \
  -days "$DAYS" -subj "/C=RU/O=HomeLab/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null
# ключ читает группа службы и никто больше
chgrp monagent "$PREFIX/tls/server.key" 2>/dev/null || true
chmod 640 "$PREFIX/tls/server.key"
chmod 644 "$PREFIX/tls/server.crt"
openssl x509 -in "$PREFIX/tls/server.crt" -noout -subject -dates
echo "внимание: ключ принадлежит группе monagent (640), а не root (600)."
echo "при 600 служба, работающая не от root, его не прочитает."

say "3. системный пользователь без оболочки"
if ! id monagent >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /sbin/nologin monagent
  echo "создан monagent"
else
  echo "monagent уже существует"
fi

say "4. unit-файл"
install -m 644 monagent.service /etc/systemd/system/monagent.service
install -m 644 logrotate /etc/logrotate.d/monagent
install -d -m 750 -o root -g adm /var/log/monagent

say "5. запуск"
systemctl daemon-reload
systemctl enable monagent
systemctl restart monagent
sleep 2
echo "состояние: $(systemctl is-active monagent)"

say "6. проверка"
curl -sk -o /dev/null -w "  /healthz -> HTTP %{http_code}\n" "https://$HOST:$PORT/healthz"
curl -sk -o /dev/null -w "  /metrics -> HTTP %{http_code}\n" "https://$HOST:$PORT/metrics"
curl -sk -o /dev/null -w "  /nope    -> HTTP %{http_code} (ожидается 404)\n" "https://$HOST:$PORT/nope"

say "7. оценка изоляции"
systemd-analyze security monagent.service --no-pager 2>/dev/null | tail -2

cat <<'MSG'

Готово. Слушает только 127.0.0.1 - наружу не выставлено, это сделано намеренно.

Проверить вручную:
  curl -sk https://127.0.0.1:8443/healthz
  curl -sk https://127.0.0.1:8443/metrics

Открыть наружу (если реально нужно):
  смените Host= и порт в monagent.service, разрешите вход в брандмауэре
  и не забудьте про TLS - самоподписанный сертификат клиенты не доверяют.

Удалить:
  systemctl disable --now monagent
  rm /etc/systemd/system/monagent.service
  rm -rf /opt/monagent
  userdel monagent
MSG
