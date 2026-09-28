#!/bin/bash
# РЈСЃС‚Р°РЅРѕРІРєР° СЃС‚РµРЅРґР° deploylab: РґРµРїР»РѕР№ СЃ РїСЂРѕРІРµСЂРєРѕР№ Р·РґРѕСЂРѕРІСЊСЏ Рё Р°РІС‚РѕРѕС‚РєР°С‚РѕРј.
# РџСЂРѕРІРµСЂРµРЅРѕ РЅР° ALT Linux 10.4, systemd 249, Python 3.9.
set -eu

ROOT=/opt/deploylab
PORT=8099

say() { printf '\n=== %s ===\n' "$1"; }

HERE="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "РЅСѓР¶РµРЅ root: sudo ./install.sh"; exit 1; }
command -v python3 >/dev/null || { echo "РЅСѓР¶РµРЅ python3"; exit 1; }
command -v curl  >/dev/null || { echo "РЅСѓР¶РµРЅ curl"; exit 1; }

# РџСЂРѕРІРµСЂСЏРµРј Р’РЎР• РЅСѓР¶РЅС‹Рµ С„Р°Р№Р»С‹ Р”Рћ С‚РѕРіРѕ, РєР°Рє С‡С‚Рѕ-С‚Рѕ СЃРѕР·РґР°С‘Рј.
# РРЅР°С‡Рµ СѓСЃС‚Р°РЅРѕРІС‰РёРє РїР°РґР°РµС‚ РЅР° СЃРµСЂРµРґРёРЅРµ СЃ РЅРµРІРЅСЏС‚РЅРѕР№ РѕС€РёР±РєРѕР№
# "install: cannot stat" Рё РѕСЃС‚Р°РІР»СЏРµС‚ РЅРµРґРѕСЃС‚СЂРѕРµРЅРЅСѓСЋ РєРѕРЅСЃС‚СЂСѓРєС†РёСЋ.
MISSING=""
for f in "releases/v1.py" "releases/v2.py" "deploy.sh" "deploylab-app.service"; do
    [ -f "$HERE/$f" ] || MISSING="$MISSING $f"
done
if [ -n "$MISSING" ]; then
    echo "install.sh Р·Р°РїСѓС‰РµРЅ РЅРµ РёР· РєР°С‚Р°Р»РѕРіР° РїСЂРѕРµРєС‚Р°, РёР»Рё С„Р°Р№Р»РѕРІ РЅРµ С…РІР°С‚Р°РµС‚."
    echo "РћР¶РёРґР°Р»РёСЃСЊ СЂСЏРґРѕРј СЃ install.sh:$MISSING"
    echo
    echo "install.sh СЃРјРѕС‚СЂРёС‚ РІ: $HERE"
    echo "РЎРєР°С‡Р°Р№С‚Рµ РІРµСЃСЊ РєР°С‚Р°Р»РѕРі deploylab С†РµР»РёРєРѕРј, Р° РЅРµ РѕРґРёРЅ С„Р°Р№Р»."
    exit 1
fi
echo "РІСЃРµ С„Р°Р№Р»С‹ РЅР° РјРµСЃС‚Рµ: $HERE"

say "1. РєР°С‚Р°Р»РѕРіРё"
install -d -m 755 "$ROOT" "$ROOT/releases" "$ROOT/bin" "$ROOT/state"
install -d -m 700 "$ROOT/state"
echo "СЃРѕР·РґР°РЅРѕ: $ROOT"

say "2. РІРµСЂСЃРёРё РїСЂРёР»РѕР¶РµРЅРёСЏ"
install -m 644 "$HERE/releases/v1.py" "$ROOT/releases/v1.py"
install -m 644 "$HERE/releases/v2.py" "$ROOT/releases/v2.py"
# v1 Рё v2 РґРѕР»Р¶РЅС‹ Р±С‹С‚СЊ С„Р°Р№Р»Р°РјРё, Р° deploy.sh Р¶РґС‘С‚ РєР°С‚Р°Р»РѕРіРё СЃ app.py
mv "$ROOT/releases/v1.py" "$ROOT/releases/v1.tmp"
mv "$ROOT/releases/v2.py" "$ROOT/releases/v2.tmp"
install -d -m 755 "$ROOT/releases/v1" "$ROOT/releases/v2"
mv "$ROOT/releases/v1.tmp" "$ROOT/releases/v1/app.py"
mv "$ROOT/releases/v2.tmp" "$ROOT/releases/v2/app.py"
echo "v1 Рё v2 СЂР°Р·Р»РѕР¶РµРЅС‹ РїРѕ РєР°С‚Р°Р»РѕРіР°Рј"
echo "СЂР°Р·Р»РёС‡РёСЏ v2 РѕС‚ v1:"
diff "$ROOT/releases/v1/app.py" "$ROOT/releases/v2/app.py" | sed 's/^/  /' || true

say "3. РїСЂРѕРІРµСЂСЏРµРј, С‡С‚Рѕ v2 Р»РѕРјР°РµС‚СЃСЏ РЅРµ СЃРёРЅС‚Р°РєСЃРёС‡РµСЃРєРё"
python3 -c "import ast; ast.parse(open('$ROOT/releases/v2/app.py').read()); print('  СЃРёРЅС‚Р°РєСЃРёСЃ РІ РїРѕСЂСЏРґРєРµ: v2 Р·Р°РїСѓСЃС‚РёС‚СЃСЏ Рё РѕС‚РІРµС‚РёС‚ РЅРµРїСЂР°РІРёР»СЊРЅРѕ')"

say "4. СЃРєСЂРёРїС‚ РґРµРїР»РѕСЏ"
install -m 755 "$HERE/deploy.sh" "$ROOT/bin/deploy.sh"
echo "СѓСЃС‚Р°РЅРѕРІР»РµРЅРѕ: $ROOT/bin/deploy.sh"

say "5. СЋРЅРёС‚ systemd"
install -m 644 "$HERE/deploylab-app.service" /etc/systemd/system/deploylab-app.service
id deploylab >/dev/null 2>&1 || useradd --system --no-create-home --shell /sbin/nologin deploylab
chown -R root:root "$ROOT"
chmod -R go-w "$ROOT"
chmod 755 "$ROOT" "$ROOT/releases" "$ROOT/releases/v1" "$ROOT/releases/v2" "$ROOT/bin"
systemctl daemon-reload
echo "СЋРЅРёС‚ Р·Р°РїРёСЃР°РЅ, РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ deploylab СЃРѕР·РґР°РЅ"

say "6. РїРµСЂРІС‹Р№ РґРµРїР»РѕР№ - РґРѕР»Р¶РµРЅ РїСЂРѕР№С‚Рё"
"$ROOT/bin/deploy.sh" "$ROOT/releases/v1" || { echo "РџР•Р Р’Р«Р™ Р”Р•РџР›РћР™ РЈРџРђР› - СЂР°Р·Р±РёСЂР°С‚СЊСЃСЏ СЂСѓРєР°РјРё"; exit 1; }
echo "РїРµСЂРІР°СЏ РІРµСЂСЃРёСЏ СЂР°Р±РѕС‚Р°РµС‚"

say "7. РїСЂРѕРІРµСЂРєР° Р°РІС‚РѕРѕС‚РєР°С‚Р° - СЃР»РѕРјР°РЅРЅР°СЏ РІРµСЂСЃРёСЏ РґРѕР»Р¶РЅР° РѕС‚РєР°С‚РёС‚СЊСЃСЏ"
echo "Р·Р°РїСѓСЃРєР°РµРј РґРµРїР»РѕР№ v2, РѕР¶РёРґР°РµРј РїСЂРѕРІР°Р» Рё РѕС‚РєР°С‚"
echo
set +e
"$ROOT/bin/deploy.sh" "$ROOT/releases/v2"
RC=$?
set -e
echo
echo "РєРѕРґ РІРѕР·РІСЂР°С‚Р° РґРµРїР»РѕСЏ v2: $RC (РѕР¶РёРґР°РµРј 1)"
echo "С‚РµРєСѓС‰Р°СЏ РІРµСЂСЃРёСЏ: $(basename "$(readlink -f "$ROOT/current")")"
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:$PORT/healthz" || true)
echo "СЃРѕСЃС‚РѕСЏРЅРёРµ РїРѕСЃР»Рµ: HTTP $CODE (РѕР¶РёРґР°РµРј 200)"

if [ "$RC" = "1" ] && [ "$CODE" = "200" ]; then
  echo
  echo "РЎР¦Р•РќРђР РР™ РЎР РђР‘РћРўРђР›: СЃР»РѕРјР°РЅРЅС‹Р№ РґРµРїР»РѕР№ РѕС‚РєР°С‚РёР»СЃСЏ, СЃРµСЂРІРёСЃ Р¶РёРІ"
else
  echo
  echo "РЎР¦Р•РќРђР РР™ РќР• РЎР РђР‘РћРўРђР›. Р–СѓСЂРЅР°Р»:"
  tail -20 "$ROOT/deploy.log" || true
  exit 1
fi

cat <<'MSG'

Р“РѕС‚РѕРІРѕ. Р§С‚Рѕ РїРѕР»СѓС‡РёР»РѕСЃСЊ:

  /opt/deploylab/current   -> РєР°РєР°СЏ РІРµСЂСЃРёСЏ Р°РєС‚РёРІРЅР° СЃРµР№С‡Р°СЃ
  /opt/deploylab/previous  -> РЅР° РєР°РєСѓСЋ РѕС‚РєР°С‚С‹РІР°С‚СЊСЃСЏ РїСЂРё СЃР»РµРґСѓСЋС‰РµРј РґРµРїР»РѕРµ
  /opt/deploylab/deploy.log -> РёСЃС‚РѕСЂРёСЏ РІСЃРµС… РґРµРїР»РѕРµРІ
  /opt/deploylab/state/known_good -> РїРѕСЃР»РµРґРЅСЏСЏ РїСЂРёРЅСЏС‚Р°СЏ РІРµСЂСЃРёСЏ

РџСЂРѕРІРµСЂРёС‚СЊ СЃРµР№С‡Р°СЃ:
  curl -s http://127.0.0.1:8099/healthz
  systemctl status deploylab-app.service
  cat /opt/deploylab/deploy.log

Р—Р°РґРµРїР»РѕРёС‚СЊ СЃРІРѕСЋ РІРµСЂСЃРёСЋ:
  РїРѕР»РѕР¶РёС‚СЊ app.py РІ /opt/deploylab/releases/v3/app.py
  /opt/deploylab/bin/deploy.sh /opt/deploylab/releases/v3

РћСЃС‚Р°РЅРѕРІРёС‚СЊ СЃС‚РµРЅРґ:
  systemctl stop deploylab-app.service
MSG
