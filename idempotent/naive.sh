#!/bin/bash
# Наивный скрипт настройки. Типичный, как пишут в первый раз.
set -u
T=/opt/idemlab

# 1. пользователь - создаём, не проверяя
useradd --system --no-create-home --shell /sbin/nologin service-app

# 2. конфиг - дописываем строки
cat >> "$T/target/app.conf" <<CFG
admin_email = ops@example.local
log_level = info
CFG

# 3. список хостов - добавляем адрес
echo "10.0.0.5" >> /var/lib/idemlab/hosts.conf

# 4. права - ставим, но если файл создаётся заново, права слетают
chmod 644 "$T/target/app.conf"
