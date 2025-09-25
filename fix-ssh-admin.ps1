# === Запустить в PowerShell от АДМИНИСТРАТОРА ===

Write-Host "=== Исправление SSH для работы с YubiKey ===" -ForegroundColor Cyan

# 1. Остановить системный ssh-agent
Write-Host "1. Останавливаем системный ssh-agent..." -ForegroundColor Yellow
try {
    Stop-Service ssh-agent -Force
    Write-Host "   ✓ ssh-agent остановлен" -ForegroundColor Green
} catch {
    Write-Host "   ⚠ Ошибка остановки: $_" -ForegroundColor Yellow
}

# 2. Отключить автозапуск ssh-agent
Write-Host "2. Отключаем автозапуск ssh-agent..." -ForegroundColor Yellow
try {
    Set-Service ssh-agent -StartupType Disabled
    Write-Host "   ✓ Автозапуск ssh-agent отключен" -ForegroundColor Green
} catch {
    Write-Host "   ⚠ Ошибка отключения: $_" -ForegroundColor Yellow
}

# 3. Проверить статус
Write-Host "3. Проверяем статус ssh-agent..." -ForegroundColor Yellow
$svc = Get-Service ssh-agent
Write-Host "   Статус: $($svc.Status)" -ForegroundColor Gray
Write-Host "   Автозапуск: $($svc.StartType)" -ForegroundColor Gray

Write-Host "`n=== Готово! ===" -ForegroundColor Green
Write-Host "Теперь ПЕРЕЗАПУСТИТЕ PowerShell и проверьте:" -ForegroundColor Yellow
Write-Host "ssh-add -L" -ForegroundColor Gray
