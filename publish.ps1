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

Step 4 "Отправляю"
Write-Host ""
Write-Host "Сейчас откроется окно входа от GitHub."
Write-Host "Введи там логин и токен. Токен я у тебя не вижу и не увижу."
Write-Host ""
Write-Host "Если окно не появилось - перечитай блок 'Что делать' ниже."
Write-Host ""

& $git push -u origin main 2>&1 | ForEach-Object { Write-Host $_ }
$rc = $LASTEXITCODE

if ($rc -ne 0) {
    Write-Host ""
    Write-Host "--- НЕ СРАБОТАЛО. Что делать ---"
    Write-Host ""
    Write-Host "1. Проверь название репозитория. Оно в адресе:"
    Write-Host "   https://github.com/ТВОЙ_ЛОГИН/НАЗВАНИЕ"
    Write-Host "   Название чувствительно к регистру и не допускает пробелов."
    Write-Host ""
    Write-Host "2. Убедись, что репозиторий создан и пуст."
    Write-Host ""
    Write-Host "3. Git мог не спросить пароль с первого раза. Тогда выполни руками:"
    Write-Host ('   cd "' + $PSScriptRoot + '"')
    Write-Host ('   &' + $git + ' push -u origin main')
    Write-Host ""
    Write-Host "4. Если просит пароль и не даёт - нужен токен, а не пароль."
    Write-Host "   GitHub: Settings - Developer settings - Personal access tokens"
    Write-Host "   Создай токен со сроком 30 дней и галочкой repo."
    Write-Host "   Вставляй его ТОЛЬКО в окно Git, не в чат и не в этот файл."
    throw "push не прошёл"
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
