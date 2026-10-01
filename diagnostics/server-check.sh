#!/bin/bash
# server-check.sh - разовая диагностика сервера.
# Не чинит ничего. Говорит, где именно сломано.
# Смысл: человек обычно не знает, что сломалось. Начинать надо с этого.
set -u
export LC_ALL=C

OK=0; WARN=0; FAIL=0
SEC="(none)"

section() { SEC="$1"; printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()   { OK=$((OK+1));   printf '  \033[32mOK\033[0m     %s\n' "$1"; }
warn() { WARN=$((WARN+1)); printf '  \033[33mВНИМАНИЕ\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  \033[31mОШИБКА\033[0m   %s\n' "$1"; }
info() { printf '         %s\n' "$1"; }

# ---------------------------------------------------------------- 1
section "1. Система"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  ok "$PRETTY_NAME"
  info "ID: $ID   версия: $VERSION_ID"
else
  fail "/etc/os-release не читается, система определена неверно"
fi
info "ядро: $(uname -r)   архитектура: $(uname -m)"
UP=$(uptime -p 2>/dev/null | sed 's/^up //')
info "работает: $UP"
H=$(df -h / | awk 'NR==2{print $4}')
U=$(df -h / | tail -1 | awk '{print $5}')
USAGE=${U%\%}
if [ "$USAGE" -ge 90 ]; then
  fail "диск занят на ${U} (свободно $H)"
elif [ "$USAGE" -ge 75 ]; then
  warn "диск занят на ${U}, скоро встанет (свободно $H)"
else
  ok "диск занят на ${U} (свободно $H)"
fi
IV=$(df -i / | tail -1 | awk '{print $5}'); IVU=${IV%\%}
if [ "$IVU" -ge 90 ]; then
  fail "свободных inode ${IV} - система упрётся в число файлов"
elif [ "$IVU" -ge 75 ]; then
  warn "свободных inode ${IV}"
else
  ok "inode: занято ${IV}"
fi
MEM=$(free -m | awk '/^Mem:/{printf "%d из %d МБ (%.0f%%)", $3, $2, $3/$2*100}')
if free -m | awk '/^Mem:/{exit ($3/$2>0.9)?0:1}'; then
  warn "память занята сильно: $MEM"
else
  ok "память: $MEM"
fi

# ---------------------------------------------------------------- 2
section "2. Сеть и открытые порты"
IPS=$(ip -4 -br addr 2>/dev/null | awk '{print $3" на "$2}' | tr '\n' ' ')
info "адреса: $IPS"
if ip -4 -br addr 2>/dev/null | grep -qE '(^| )10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.'; then
  info "есть приватный адрес - наружу нужно пробрасывать порт на роутере"
fi
NL=$(ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | sort -u)
CNT=$(echo "$NL" | grep -c . )
info "слушающих сокетов: $CNT"
LOOP=$(echo "$NL" | grep -c '^127\.0\.0\.1\|^::1')
if [ "$LOOP" -gt 0 ]; then
  info "из них только на loopback (снаружи недоступны): $LOOP"
fi
ALL=$(echo "$NL" | grep -c '^\*\|^0\.0\.0\.0')
info "слушают на всех интерфейсах: $ALL"
[ "$ALL" -gt 0 ] && ss -ltn 2>/dev/null | awk 'NR>1 && ($4 ~ /^\*/ || $4 ~ /^0\.0\.0\.0/){printf "         %s\n", $4}' | sort -u | head -8
EXT=$(curl -s --max-time 6 https://api.ipify.org 2>/dev/null)
if [ -n "$EXT" ]; then
  info "внешний адрес: $EXT"
  if [ -n "${INT:-}" ] && [ "$EXT" != "$INT" ]; then :; fi
else
  info "внешний адрес определить не удалось (нет интернета или curl)"
fi

# ---------------------------------------------------------------- 3
section "3. SSH - самая частая дыра"
CF=""
for c in /etc/openssh/sshd_config /etc/ssh/sshd_config; do
  [ -f "$c" ] && { CF="$c"; break; }
done
if [ -z "$CF" ]; then
  fail "конфиг sshd не найден ни в /etc/openssh/, ни в /etc/ssh/"
  info "в ALT путь /etc/openssh/sshd_config, в Debian и RHEL - /etc/ssh/sshd_config"
else
  ok "конфиг: $CF"
  if [ "$CF" = "/etc/openssh/sshd_config" ]; then
    info "это путь ALT. В интернете чаще пишут /etc/ssh/sshd_config - не путайте"
  fi
  E=$(/usr/sbin/sshd -T 2>/dev/null)
  if [ -z "$E" ]; then
    warn "sshd -T не отдал параметров (нужен root)"
  else
    PA=$(echo "$E" | grep -m1 '^passwordauthentication' | awk '{print $2}')
    PR=$(echo "$E" | grep -m1 '^permitrootlogin' | awk '{print $2}')
    KB=$(echo "$E" | grep -m1 '^kbdinteractiveauthentication' | awk '{print $2}')
    PU=$(echo "$E" | grep -m1 '^pubkeyauthentication' | awk '{print $2}')
    [ "$PA" = "yes" ] && fail "парольный вход ВКЛЮЧЁН (passwordauthentication yes)" || ok "парольный вход выключен"
    [ "$PU" = "yes" ] && ok "вход по ключу включён" || fail "вход по ключу ВЫКЛЮЧЕН"
    [ "$KB" = "yes" ] && warn "клавиатурная аутентификация включена - минус пароля" || ok "клавиатурная аутентификация выключена"
    case "$PR" in
      without-password|no) warn "root может войти по ключу ($PR)" ;;
      yes) fail "root может войти по паролю!" ;;
      *) ok "вход root ограничен ($PR)" ;;
    esac
  fi
  SYN=$(journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -ci 'Failed password')
  SYK=$(journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -ci 'Failed publickey')
  if [ "$SYN" -gt 20 ]; then
    warn "неудачных входов по паролю за сутки: $SYN"
    journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -i 'Failed password' \
      | awk '{for(i=1;i<=NF;i++) if($i=="from") print $(i+1)}' | sort | uniq -c | sort -rn | head -3 | sed 's/^/         /'
  elif [ "$SYN" -gt 0 ]; then
    info "неудачных входов по паролю за сутки: $SYN"
  else
    ok "неудачных входов по паролю за сутки нет"
  fi
  [ "$SYK" -gt 0 ] && info "неудачных входов по ключу за сутки: $SYK"
fi

# ---------------------------------------------------------------- 4
section "4. Права и sudo"
SUDOERS_OK=$(LC_ALL=C visudo -c 2>&1 | grep -c 'parsed OK')
if [ "$SUDOERS_OK" -ge 1 ]; then
  ok "sudoers разбирается без ошибок"
  LC_ALL=C visudo -c 2>&1 | grep -v 'parsed OK' | sed 's/^/         /' | head -4
else
  fail "в sudoers есть ошибки - sudo может не работать"
  LC_ALL=C visudo -c 2>&1 | head -4 | sed 's/^/         /'
fi
if [ -r /etc/sudoers ]; then
  for f in $(LC_ALL=C visudo -c 2>&1 | grep -oE '/etc/sudoers[^ ]*' | sort -u); do
    :
  done
fi
BAD=$(LC_ALL=C visudo -c 2>&1 | grep -oE '/etc/sudoers\.d/[^ :]+' | sort -u)
for f in $BAD; do
  M=$(stat -c '%a' "$f" 2>/dev/null)
  case "$M" in
    400|440) ok "$(basename $f) права $M" ;;
    *) warn "$(basename $f) права $M - ALT требует 400, в Debian и RHEL ставят 440" ;;
  esac
done

# ---------------------------------------------------------------- 5
section "5. Службы"
F=$(systemctl list-units --state=failed --no-legend --no-pager 2>/dev/null | wc -l)
if [ "$F" -gt 0 ]; then
  fail "упавших служб: $F"
  systemctl list-units --state=failed --no-legend --no-pager 2>/dev/null | awk '{print "         "$1}' | head -8
else
  ok "упавших служб нет"
fi
RS=$(systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | wc -l)
info "работает служб: $RS"
J=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMG]' | head -1)
info "журнал системы занимает: ${J:-неизвестно}"
JP=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?%' | head -1)
if [ -n "$JP" ]; then
  JN=${JP%\%}
  if [ "$JN" -ge 85 ]; then
    fail "журнал заполнил $JP файловой системы"
    info "поможет: journalctl --vacuum-size=500M"
  elif [ "$JN" -ge 60 ]; then
    warn "журнал занял $JP файловой системы"
  else
    ok "журнал занял $JP"
  fi
fi
LDEL=$(ls -l /proc/*/fd 2>/dev/null | grep -c 'deleted')
if [ "$LDEL" -gt 0 ]; then
  warn "открытых удалённых файлов: $LDEL - место не освободится, пока их держат процессы"
  info "найти: lsof +L1"
fi

# ---------------------------------------------------------------- 6
section "6. Безопасность"
S=$(command -v getenforce >/dev/null && getenforce 2>/dev/null || echo "")
if [ -n "$S" ]; then
  case "$S" in
    Enforcing) ok "SELinux: $S (работает)" ;;
    Permissive) warn "SELinux: $S (только пишет в лог, не защищает)" ;;
    *) ok "SELinux: $S" ;;
  esac
else
  info "SELinux: не установлен либо не проверяется"
fi
FP=$(rpm -q firewalld nftables ufw 2>/dev/null | grep -c 'пакета не установлено')
if [ "$FP" -ge 3 ]; then
  warn "ни firewalld, ни nftables, ни ufw не установлено - файрвола нет"
fi
IPT=$(iptables -S 2>/dev/null | grep -c '^-A')
POL=$(iptables -S 2>/dev/null | grep '^-P INPUT' | awk '{print $3}')
if [ "$POL" = "ACCEPT" ] && [ "$IPT" = "0" ]; then
  warn "iptables: политика ACCEPT и 0 правил - файрвол не фильтрует ничего"
fi
# ЛОЖНАЯ ТРЕВОГА: раньше условие было ($2=="0"||length($2)<2)
# и ловило ВСЕ системные учётки, у которых в поле пароля "!��� или "*" -
# это заблокированные учётки, а не пустые пароли. Ошибка в 26 пунктах.
# Ловим ТОЛЬКО по-настоящему пустое поле: без пароля можно войти вообще.
P=$(awk -F: '$2==""{c++} END{print c+0}' /etc/shadow 2>/dev/null)
if [ "$P" -gt 0 ]; then
  fail "учёток БЕЗ пароля: $P - вход возможен с пустым паролем"
  awk -F: '$2==""{print "         "$1}' /etc/shadow 2>/dev/null | head -5
else
  ok "учёток без пароля нет (заблокированные ! и * в счёт не идут)"
fi
LOCKED=$(awk -F: '$2=="!"||$2=="*"{c++} END{print c+0}' /etc/shadow 2>/dev/null)
info "заблокированных учёток (пароль ! или *): $LOCKED - это нормально"
LASTB=$(lastb -n 200 2>/dev/null | grep -vc '^$')
info "неудачных попыток входа всего в btmp: $LASTB"
U=$(awk -F: '$3==0 && $1!="root"{c++} END{print c+0}' /etc/passwd)
if [ "$U" -gt 0 ]; then
  warn "обычных пользователей с uid 0: $U - это серьёзно"
  awk -F: '$3==0 && $1!="root"{print "         "$1}' /etc/passwd | head -5
else
  ok "uid 0 есть только у root"
fi

# ---------------------------------------------------------------- 7
section "7. Обновления и время"
# grep -c при нуле совпадений печатает 0 И возвращает код 1.
# С "|| echo 0" в переменную попадает "0\n0" - отсюда падение
# арифметики в [ ]. Поэтому НЕ пишем || echo 0, а чистим отдельно.
UPD=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ')
[ -z "$UPD" ] && UPD=0
case "$UPD" in *[!0-9]*) UPD=0 ;; esac
if [ "$UPD" -gt 30 ]; then
  warn "доступных обновлений пакетов: $UPD"
elif [ "$UPD" -gt 0 ]; then
  info "доступных обновлений: $UPD"
else
  ok "неустановленных обновлений нет"
fi
if command -v chronyc >/dev/null 2>&1; then
  # ОШИБКА, найденная на живой машине: было awk '/Leap status/{print $3}'.
  # Реальная строка выглядит "Leap status     : Normal", поэтому $3 - это
  # двоеточие, и в отчёт попадало "синхронизация времени: :".
  # Номер поля нельзя фиксировать: при "Not synchronised" слов больше
  # и значение съедет на другой номер. Поэтому берём всё ПОСЛЕ двоеточия.
  OFF=$(chronyc tracking 2>/dev/null | sed -n 's/^Leap status[[:space:]]*:[[:space:]]*//p')
  case "$OFF" in
    *ynchronis*|*ynchroniz*)
      fail "время не синхронизировано (Leap status: $OFF) - TLS и логи будут врать" ;;
    '')
      warn "chronyc не ответил - состояние времени неизвестно" ;;
    *)
      ok "синхронизация времени: $OFF"
      ST=$(chronyc tracking 2>/dev/null | sed -n 's/^Stratum[[:space:]]*:[[:space:]]*//p')
      case "$ST" in
        ''|*[!0-9]*) : ;;
        *) [ "$ST" -gt 5 ] && info "stratum $ST - источник времени далёк, точность ниже" ;;
      esac ;;
  esac
fi

# ---------------------------------------------------------------- 8
section "8. Что делать дальше"
printf '\n'
if [ "$FAIL" -gt 0 ]; then
  echo "  Сначала ОШИБКИ: $FAIL шт. Их надо закрыть, остальное подождёт."
elif [ "$WARN" -gt 0 ]; then
  echo "  Критичных ошибок нет. Предупреждений: $WARN - посмотрите по списку."
else
  echo "  Явных проблем не найдено. Это не значит «всё хорошо» - это значит," 
  echo "  что стандартные проверки пройдены."
fi
echo "  ИТОГО: проверок с проблемами $((FAIL + WARN)), из них ошибок $FAIL, предупреждений $WARN"
echo
echo "  Разбор конкретного пункта: journalctl -p err --since '1 hour ago' --no-pager"
echo "  Полный лог службы:        journalctl -u ИМЯ --no-pager -n 50"
echo "  Проверить порт снаружи:    nc -zv -w 5 ВАШ_IP ПОРТ  (с мобильного интернета!)"
exit $((FAIL > 0 ? 1 : 0))