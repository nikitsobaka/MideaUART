# === Проверка настройки YubiKey + GPG + SSH ===

Write-Host "=== Проверка YubiKey + GPG настройки ===" -ForegroundColor Cyan

# Проверяем переменные окружения
Write-Host "`n1. SSH_AUTH_SOCK:" -ForegroundColor Yellow
Write-Host "   $env:SSH_AUTH_SOCK"
if ($env:SSH_AUTH_SOCK -ne "\\.\pipe\gnupg\ssh") {
    Write-Warning "   SSH_AUTH_SOCK не настроен! Выполните: `$env:SSH_AUTH_SOCK = '\\.\pipe\gnupg\ssh'"
}

# Проверяем Git конфигурацию
Write-Host "`n2. Git GPG конфигурация:" -ForegroundColor Yellow
$gitGpgProgram = git config --global gpg.program
$gitSigningKey = git config --global user.signingkey
$gitCommitGpgSign = git config --global commit.gpgsign

Write-Host "   gpg.program: $gitGpgProgram"
Write-Host "   user.signingkey: $gitSigningKey"
Write-Host "   commit.gpgsign: $gitCommitGpgSign"

# Проверяем YubiKey
Write-Host "`n3. YubiKey статус:" -ForegroundColor Yellow
$cardStatus = gpg --card-status 2>$null
if ($cardStatus) {
    $serial = ($cardStatus | Select-String "Serial number").Line
    $signature = ($cardStatus | Select-String "Signature key").Line
    Write-Host "   ✓ YubiKey обнаружен: $serial" -ForegroundColor Green
    Write-Host "   ✓ Ключ подписи: $signature" -ForegroundColor Green
} else {
    Write-Warning "   YubiKey не обнаружен или не настроен"
}

# Проверяем GPG подпись
Write-Host "`n4. Тест GPG подписи:" -ForegroundColor Yellow
$testText = "test signature"
$testFile = "test-gpg.txt"
$testText | Out-File -FilePath $testFile -Encoding UTF8

try {
    $signResult = gpg --clear-sign $testFile 2>&1
    if (Test-Path "$testFile.asc") {
        Write-Host "   ✓ GPG подпись работает!" -ForegroundColor Green
        Remove-Item $testFile, "$testFile.asc" -Force
    } else {
        Write-Warning "   Ошибка GPG подписи: $signResult"
    }
} catch {
    Write-Warning "   Ошибка при тестировании GPG: $_"
}

# Проверяем SSH ключи
Write-Host "`n5. SSH ключи через gpg-agent:" -ForegroundColor Yellow
$sshKeys = ssh-add -L 2>&1
if ($sshKeys -and $sshKeys -notmatch "Error|no identities") {
    Write-Host "   ✓ SSH ключ найден:" -ForegroundColor Green
    Write-Host "   $($sshKeys[0].Substring(0, 80))..." -ForegroundColor Gray
} else {
    Write-Warning "   SSH ключи не найдены: $sshKeys"
    Write-Host "   Попробуйте перезапустить терминал или выполните: gpg-connect-agent /bye" -ForegroundColor Gray
}

# Информация для настройки Git-сервисов
Write-Host "`n=== Что нужно добавить в GitHub/GitLab ===" -ForegroundColor Cyan

Write-Host "`n📋 GPG публичный ключ (добавить в Settings → SSH and GPG keys):"
Write-Host "gpg --armor --export $gitSigningKey" -ForegroundColor Gray

if ($sshKeys -and $sshKeys -notmatch "Error|no identities") {
    Write-Host "`n🔑 SSH публичный ключ:"
    Write-Host "$($sshKeys[0])" -ForegroundColor Gray
}

Write-Host "`n=== Готово! ===" -ForegroundColor Green
Write-Host "Теперь все коммиты будут автоматически подписываться YubiKey!" -ForegroundColor Green
