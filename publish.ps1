# publish.ps1 - отправляет локальный репозиторий на GitHub.
#
# ВАЖНО: паролей и токенов в этом файле нет и не будет.
# Логин и пароль спросит Git Credential Manager - отдельным окном.
#
# ГЛАВНОЕ ПРАВИЛО ЭТОГО ФАЙЛА: git пишет ход работы в stderr, а
# PowerShell при ErrorActionPreference=Stop считает это фатальной
# ошибкой и обрывает скрипт на первой строке "To https://...".
# Поэтому ВСЕ вызовы git идут через Git-Run, который временно
# переключает режим и возвращает код возврата, а не исключение.

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$git = "D:\Git\cmd\git.exe"
if (-not (Test-Path $git)) { $git = "git" }
Set-Location $PSScriptRoot

# --- безопасный вызов git: никогда не роняет скрипт ---
function Git-Run {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GArgs)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $lines = & $git @GArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    foreach ($l in $lines) {
        $s = [string]$l
        if ($s -and $s -notmatch '^\s*$') { Write-Host "   $s" }
    }
    return $code
}

function Say($t) { Write-Host ""; Write-Host "--- $t ---" }

Say "1. Проверяю репозиторий"
$c = Git-Run "rev-parse" "--git-dir"
if ($c -ne 0) { Write-Host "Это не git-репозиторий"; exit 1 }

$dirty = (Git-Run "status" "--porcelain")
if ($dirty -eq 0) { $isDirty = $true } else { $isDirty = $false }
$dirtyOut = & $git status --porcelain 2>$null
if ($dirtyOut) {
    Write-Host "Есть незакоммиченные изменения, коммичу."
    Git-Run "add" "-A" | Out-Null
    Git-Run "commit" "-q" "-m" "update" | Out-Null
}
$files = (& $git ls-files | Measure-Object).Count
Write-Host "Файлов под контролем: $files"
Write-Host "Коммитов локально: $(& $git rev-list --count main 2>$null)"

Say "2. Имя и почта для подписи коммитов"
$name = & $git config user.name
$mail = & $git config user.email
if ($name -eq "CHANGE-ME" -or [string]::IsNullOrWhiteSpace($name)) {
    $name = Read-Host "Имя для подписи"
}
if ([string]::IsNullOrWhiteSpace($name)) { $name = "Linux Author" }
if ($mail -eq "change-me@example.com" -or [string]::IsNullOrWhiteSpace($mail)) {
    $mail = Read-Host "Почта для коммитов"
}
if ([string]::IsNullOrWhiteSpace($mail)) { $mail = "$name@localhost" }
& $git config user.name $name | Out-Null
& $git config user.email $mail | Out-Null
Write-Host "Подпись: $name <$mail>  (только этот репозиторий)"

Say "3. Адрес репозитория"
$user = Read-Host "Логин на GitHub (без https:// и без @)"
$repo = Read-Host "Название репозитория"
if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($repo)) {
    Write-Host "Нужен логин и название"; exit 1
}
$url = "https://github.com/$user/$repo.git"
Write-Host "Адрес: $url"
Git-Run "remote" "remove" "origin" | Out-Null
Git-Run "remote" "add" "origin" $url | Out-Null

Say "4. Имя ветки"
$branch = & $git branch --show-current
if ($branch -ne "main") {
    Write-Host "Было: $branch  ->  меняю на main (GitHub ждёт main)"
    Git-Run "branch" "-M" "main" | Out-Null
}
Write-Host "Ветка: $(& $git branch --show-current)"

Say "5. Отправляю"
Write-Host "Откроется окно входа от GitHub. Введи там логин и токен."
Write-Host "Я его не вижу."
Write-Host ""
$rc = Git-Run "push" "-u" "origin" "main"

if ($rc -ne 0) {
    Write-Host ""
    Write-Host "=== ПЕРВАЯ ПОПЫТКА НЕ ПРОШЛА. РАЗБИРАЮСЬ ==="
    Write-Host ""
    Git-Run "fetch" "origin" | Out-Null

    $localHash = (& $git rev-parse main 2>$null)
    $remoteLine = (& $git ls-remote origin refs/heads/main 2>$null)
    $remoteHash = $null
    if ($remoteLine) { $remoteHash = ($remoteLine -split '\s+')[0] }

    Write-Host "локальный коммит: $(if($localHash){$localHash.Substring(0,7)}else{'?'})"
    Write-Host "коммит на GitHub: $(if($remoteHash){$remoteHash.Substring(0,7)}else {'нет ветки main'})"
    Write-Host ""

    if ($remoteHash -and $remoteHash -ne $localHash) {
        $rlog = (& $git log --oneline origin/main 2>$null | Measure-Object).Count
        Write-Host "На GitHub лежит $rlog коммит(ов) плюс автосозданный README.md."
        if ($rlog -le 2) {
            Write-Host "Это пустой репозиторий. Наш README его заменит, ничего"
            Write-Host "ценного там нет и потерять нечего."
            Write-Host ""
            $ans = Read-Host "Перезаписать? (y/N)"
            if ($ans -eq "y") {
                Write-Host "Отправляю с --force"
                $rc = Git-Run "push" "-u" "origin" "main" "--force"
            }
        } else {
            Write-Host "На GitHub больше коммитов, чем у нас. Возможно это чужой"
            Write-Host "репозиторий. Перезаписывать не буду - спроси."
            $ans = Read-Host "Перезаписать всё равно? (y/N)"
            if ($ans -eq "y") { $rc = Git-Run "push" "-u" "origin" "main" "--force" }
        }
    }
}

if ($rc -ne 0) {
    Write-Host ""
    Write-Host "=== НЕ ПОЛУЧИЛОСЬ ==="
    Write-Host ""
    Write-Host "Скопируй этот текст и пришли мне - разберу."
    Write-Host ""
    Write-Host "Частые причины:"
    Write-Host "  1. Репозиторий не создан или имя указано неверно."
    Write-Host "  2. Пароль GitHub не подходит для git - нужен токен."
    Write-Host "     GitHub: Settings - Developer settings - Personal access tokens"
    Write-Host "     Tokens (classic) - Generate new token, 30 дней, галочка repo."
    Write-Host "     Вставляй токен ТОЛЬКО в окно Git."
    Write-Host "  3. Отклонил браузер на запрос входа."
    exit 1
}

Write-Host ""
Write-Host "=== ОТПРАВЛЕНО ==="
Write-Host ""
Write-Host "Репозиторий: https://github.com/$user/$repo"
Write-Host ""
Write-Host "Ссылки для статей:"
Write-Host "  https://github.com/$user/$repo/blob/main/monagent/install.sh"
Write-Host "  https://github.com/$user/$repo/blob/main/backup/install.sh"
Write-Host ""
Write-Host "Прямые ссылки на скачивание:"
Write-Host "  https://raw.githubusercontent.com/$user/$repo/main/backup/appdata-verify.sh"
Write-Host "  https://raw.githubusercontent.com/$user/$repo/main/monagent/monagent.py"
Write-Host ""
Write-Host "Токен после этого можно отозвать:"
Write-Host "  Settings - Developer settings - Personal access tokens - Delete"
exit 0
