# publish.ps1 - отправляет локальный репозиторий на GitHub.
#
# ВАЖНО: в этом файле нет и не будет паролей и токенов.
# Логин и пароль спросит Git Credential Manager - отдельным окном.
# В этот чат, в файлы и в историю ничего секретного не попадает.
#
# Идёт в паре с ОПУБЛИКОВАТЬ.bat, который зовёт этот файл.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$git = "D:\Git\cmd\git.exe"
if (-not (Test-Path $git)) { $git = "git" }
Set-Location $PSScriptRoot

function Step($n, $t) { Write-Host ""; Write-Host "--- $n. $t ---" }

Step 1 "Проверяю репозиторий"
& $git rev-parse --git-dir 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Это не git-репозиторий. Папка должна содержать .git" }
& $git status --short | Out-Null
$dirty = & $git status --porcelain
if ($dirty) {
    Write-Host "Есть незакоммиченные изменения, добавляю и коммичу."
    & $git add -A | Out-Null
    & $git commit -q -m "update" | Out-Null
}
Write-Host "Файлов под контролем: $((& $git ls-files | Measure-Object).Count)"

Step 2 "Имя и почта для подписи коммитов"
$name = & $git config user.name
$mail = & $git config user.email
if ($name -eq "CHANGE-ME" -or [string]::IsNullOrWhiteSpace($name)) {
    $name = Read-Host "Как тебя подписать в коммитах (имя)"
}
if ([string]::IsNullOrWhiteSpace($name)) { $name = "Linux Author" }
if ($mail -eq "change-me@example.com" -or [string]::IsNullOrWhiteSpace($mail)) {
    $mail = Read-Host "Почта для коммитов"
}
if ([string]::IsNullOrWhiteSpace($mail)) { $mail = "$name@localhost" }
& $git config user.name $name
& $git config user.email $mail
Write-Host "Подпись: $name <$mail>  (только для этого репозитория)"
Write-Host "Поменять позже: git config user.name 'Имя'"

Step 3 "Адрес репозитория на GitHub"
$user = Read-Host "Твой логин на GitHub (без https:// и без @)"
$repo = Read-Host "Название репозитория"
if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($repo)) {
    throw "Нужен логин и название репозитория"
}
$url = "https://github.com/$user/$repo.git"
Write-Host "Адрес: $url"

$existing = & $git remote get-url origin 2>&1
if ($LASTEXITCODE -eq 0 -and $existing) {
    Write-Host "origin уже был: $existing"
    $ch = Read-Host "Перезаписать? (y/N)"
    if ($ch -ne "y") { throw "Отмена - ничего не меняю" }
}
& $git remote set-url origin $url

Step 4 "Имя ветки"
# Ветка по умолчанию у git бывает master, а GitHub ждёт main.
# Если ветка называется иначе - переименовываем, иначе push упадёт.
$branch = & $git branch --show-current
Write-Host "текущая ветка: $branch"
if ($branch -ne "main") {
    Write-Host "переименовываю $branch -> main"
    & $git branch -M main
}
Write-Host "ветка: $(& $git branch --show-current)"

Step 5 "Отправляю"
Write-Host ""
Write-Host "Сейчас откроется окно входа от GitHub."
Write-Host "Введи там логин и токен. Токен я у тебя не вижу и не увижу."
Write-Host ""

& $git push -u origin main 2>&1 | ForEach-Object { Write-Host $_ }
$rc = $LASTEXITCODE

if ($rc -ne 0) {
    Write-Host ""
    Write-Host "--- СНАЧАЛА ПОНИМАЕМ, ЧТО ИМЕННО НЕ ТАК ---"
    & $git fetch origin 2>&1 | ForEach-Object { Write-Host "   $_" }
    $remoteCount = 0
    $r = & $git rev-list --count origin/main 2>$null
    if ($r) { $remoteCount = [int]$r }
    $localCount = [int](& $git rev-list --count main)
    Write-Host ""
    Write-Host "коммитов локально:  $localCount"
    Write-Host "коммитов на GitHub: $remoteCount"
    Write-Host ""

    if ($remoteCount -le 2 -and $localCount -gt $remoteCount) {
        Write-Host "На GitHub 1-2 коммита - почти наверняка автосозданный README.md"
        Write-Host "от самого GitHub. Он пустой и заменится нашим."
        Write-Host ""
        $ans = Read-Host "Перезаписать историю на GitHub? (y/N)"
        if ($ans -eq "y") {
            & $git push -u origin main --force 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -eq 0) { $rc = 0; Write-Host "получилось" }
        }
    }

    if ($rc -ne 0) {
        Write-Host ""
        Write-Host "--- ЧТО ДЕЛАТЬ ---"
        Write-Host ""
        Write-Host "1. Проверь адрес: https://github.com/$user/$repo"
        Write-Host "   Регистр важен, пробелы не допускаются."
        Write-Host ""
        Write-Host "2. Выполни руками:"
        Write-Host ('   cd "' + $PSScriptRoot + '"')
        Write-Host ('   &' + $git + ' push -u origin main --force')
        Write-Host ""
        Write-Host "3. Если пароль не подходит - нужен токен."
        Write-Host "   GitHub: Settings - Developer settings - Personal access tokens"
        Write-Host "   Tokens (classic) - Generate new token, 30 дней, галочка repo."
        Write-Host "   Вставляй токен ТОЛЬКО в окно Git. Не в чат, не в файлы."
        throw "push не прошёл"
    }
}

Write-Host ""
Write-Host "--- УСПЕШНО ОТПРАВЛЕНО ---"
Write-Host ""
Write-Host "Репозиторий: https://github.com/$user/$repo"
Write-Host ""
Write-Host "Ссылка на конкретный файл для статей:"
Write-Host "https://github.com/$user/$repo/blob/main/monagent/install.sh"
Write-Host "https://github.com/$user/$repo/blob/main/backup/install.sh"
Write-Host ""
Write-Host "Сырая ссылка (удобнее для скачивания):"
Write-Host "https://raw.githubusercontent.com/$user/$repo/main/backup/appdata-verify.sh"
Write-Host ""
Write-Host "Теперь токен можно отозвать на GitHub:"
Write-Host "Settings - Developer settings - Personal access tokens - Delete"
