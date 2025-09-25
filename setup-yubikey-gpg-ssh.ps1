# === Setup YubiKey + GPG + SSH for Windows 11 ===
# Требования: установлен Gpg4win (gpg, gpg-agent), включён OpenSSH Client в Windows.

Write-Host "== Проверка OpenSSH Client ==" -ForegroundColor Cyan
$sshVer = (& ssh -V) 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Error "OpenSSH Client не найден. Включите его: Параметры → Приложения → Доп. компоненты → OpenSSH Client."
  exit 1
}
Write-Host $sshVer

# Опционально: отключить конфликтующий сервис Windows 'ssh-agent'
# (gpg-agent будет играть роль ssh-agent через SSH_AUTH_SOCK).
Write-Host "== Отключение системного сервиса ssh-agent (опционально) ==" -ForegroundColor Cyan
try {
  $svc = Get-Service -Name ssh-agent -ErrorAction Stop
  if ($svc.Status -ne 'Stopped') { 
    Write-Host "Попытка остановить ssh-agent..." -ForegroundColor Yellow
    # Stop-Service ssh-agent -Force 
  }
  # Set-Service ssh-agent -StartupType Disabled
  Write-Host "Системный ssh-agent обнаружен. Рекомендуется отключить вручную от администратора." -ForegroundColor Yellow
} catch {
  Write-Host "Сервис ssh-agent не найден или уже отключён — пропускаю." -ForegroundColor DarkGray
}

# Пути GnuPG
$gnupgHome = Join-Path $env:APPDATA 'gnupg'
if (!(Test-Path $gnupgHome)) { New-Item -ItemType Directory -Path $gnupgHome | Out-Null }
$gpgAgentConf = Join-Path $gnupgHome 'gpg-agent.conf'

Write-Host "== Настройка gpg-agent.conf (TTL = 24h, SSH support) ==" -ForegroundColor Cyan
$currentConf = ""
if (Test-Path $gpgAgentConf) {
    $currentConf = Get-Content $gpgAgentConf -Raw
}

$requiredSettings = @(
    "enable-ssh-support",
    "default-cache-ttl 86400",
    "max-cache-ttl 86400"
)

$needsUpdate = $false
foreach ($setting in $requiredSettings) {
    if ($currentConf -notmatch [regex]::Escape($setting.Split(' ')[0])) {
        $needsUpdate = $true
        break
    }
}

if ($needsUpdate) {
    @"
# Включаем SSH поддержку
enable-ssh-support
enable-putty-support
use-standard-socket

# Настройки кэширования (в секундах)
default-cache-ttl 86400        # 24 часа
max-cache-ttl 86400           # 24 часа

# Настройки для YubiKey
max-cache-ttl-ssh 86400       # 24 часа кэширования SSH
default-cache-ttl-ssh 86400   # 24 часа по умолчанию

# Отключаем PIN попадание в кэш
no-allow-external-cache
"@ | Set-Content -Path $gpgAgentConf -Encoding UTF8
    Write-Host "Обновлён: $gpgAgentConf" -ForegroundColor Green
} else {
    Write-Host "gpg-agent.conf уже настроен корректно" -ForegroundColor Green
}

# Перезапуск gpg-agent
Write-Host "== Перезапуск gpg-agent ==" -ForegroundColor Cyan
& gpgconf --kill gpg-agent | Out-Null
Start-Sleep -Seconds 1

# Прописать SSH_AUTH_SOCK (для текущего пользователя, постоянная запись)
Write-Host "== Установка SSH_AUTH_SOCK для gpg-agent ==" -ForegroundColor Cyan
$sshSock = "\\.\pipe\gnupg\ssh"
& setx SSH_AUTH_SOCK $sshSock | Out-Null
$env:SSH_AUTH_SOCK = $sshSock
Write-Host "SSH_AUTH_SOCK = $sshSock" -ForegroundColor DarkGray

# Найти gpg.exe для Git
Write-Host "== Поиск gpg.exe ==" -ForegroundColor Cyan
$gpgPath = (Get-Command gpg.exe -ErrorAction SilentlyContinue).Source
if (-not $gpgPath) {
  $gpgPath = "C:\Program Files (x86)\GnuPG\bin\gpg.exe"
}
if (!(Test-Path $gpgPath)) {
  Write-Error "gpg.exe не найден. Установите Gpg4win и перезапустите скрипт."
  exit 1
}
Write-Host "gpg.exe: $gpgPath" -ForegroundColor DarkGray

# Настройки Git для GPG-подписей
Write-Host "== Настройка Git для GPG-подписей ==" -ForegroundColor Cyan
& git config --global gpg.program "$gpgPath"
& git config --global commit.gpgsign true

# Пытаемся автоматически определить KeyID (Fingerprint) для подписи из YubiKey.
Write-Host "== Попытка определить GPG KeyID с карты ==" -ForegroundColor Cyan
$card = & gpg --card-status 2>$null
$fpr = $null
if ($card) {
  # Ищем строку "Signature key"
  $sigLine = $card | Select-String "Signature key" | Select-Object -First 1
  if ($sigLine) {
    $fpr = ($sigLine.Line -split '\s+')[-1] -replace '\s+', ''
  }
}

if (-not $fpr) {
  # fallback: берем первый публичный ключ из локального keyring
  $list = & gpg --list-keys --with-colons 2>$null
  if ($list) {
    $fps = $list -split "`n" | Where-Object { $_ -like "fpr:*" } | ForEach-Object { ($_ -split ':')[9] } | Where-Object { $_ } | Select-Object -First 1
    $fpr = $fps
  }
}

if ($fpr) {
  & git config --global user.signingkey $fpr
  Write-Host "Git user.signingkey = $fpr" -ForegroundColor Green
} else {
  Write-Warning "Не удалось автоматически определить ключ для подписи. Позже задайте вручную: git config --global user.signingkey <KeyID>"
}

# Запуск gpg-agent и проверка SSH-ключа
Write-Host "== Проверка SSH ключа от YubiKey ==" -ForegroundColor Cyan
Write-Host "Вставьте YubiKey, при необходимости коснитесь сенсора/введите PIN..." -ForegroundColor Yellow

# Запускаем gpg-agent
& gpg-connect-agent /bye | Out-Null
Start-Sleep -Seconds 2

$sshKeys = & ssh-add -L 2>&1
if ($LASTEXITCODE -ne 0 -or -not $sshKeys -or ($sshKeys -match "error|no identities")) {
  Write-Warning "SSH ключ не получен. Убедитесь, что:
  1) Вставлен YubiKey,
  2) Включён 'Authentication' subkey на карте (OpenPGP),
  3) Перезапустите терминал для применения SSH_AUTH_SOCK."
} else {
  Write-Host "Обнаружен публичный SSH-ключ (из YubiKey через gpg-agent):" -ForegroundColor Green
  $sshKeys | Write-Output

  # Сохраним в файл, чтобы было удобно добавить на Git-сервер
  $outFile = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\id_yubikey_pub.txt'
  $sshKeys | Set-Content -Path $outFile -Encoding UTF8
  Write-Host "Сохранено в: $outFile" -ForegroundColor DarkGray
}

Write-Host "`n== Готово ==" -ForegroundColor Green
Write-Host "• Добавьте GPG public ключ в ваш Git-сервис: gpg --armor --export $fpr" -ForegroundColor Yellow
Write-Host "• Добавьте SSH public ключ (из файла id_yubikey_pub.txt) в ваш Git-сервис." -ForegroundColor Yellow
Write-Host "• Проверка: ssh -T git@github.com (или ваш хост) — должен спросить PIN/Hello при первом обращении (кэш 24ч)." -ForegroundColor Yellow
Write-Host "• Теперь все коммиты будут автоматически подписываться YubiKey!" -ForegroundColor Green
