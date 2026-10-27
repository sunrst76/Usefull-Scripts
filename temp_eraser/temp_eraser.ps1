# Список путей для очистки
$TargetPaths = @(
    [System.IO.Path]::GetTempPath(),
    "$env:SystemRoot\Temp",
    "$env:SystemRoot\Prefetch"    
)

Write-Host "=== Запуск очистки временных файлов ===" -ForegroundColor Cyan

# 1. Очистка папок 
foreach ($Path in $TargetPaths) {
    
    if (Test-Path $Path) {
        Write-Host "Очистка папки: $Path" -ForegroundColor Yellow

        # Переходим в целевую папку
        Set-Location -Path $Path

        # Удаляем все файлы (включая скрытые и системные) без лишних вопросов
        cmd.exe /c "del /f /q /a * 2>nul"
        
        # Удаляем все подпапки со всем содержимым (включая GUID-папки)
        cmd.exe /c "for /d %i in (*) do rmdir /s /q `"%i`" 2>nul"
    }
}
# 2. Очистка корзины (работает в Win 10/11)
Write-Host "Очистка корзины..." -ForegroundColor Yellow
try {
    Clear-RecycleBin -Force -ErrorAction Stop
    Write-Host "Корзина успешно очищена." -ForegroundColor Green
}
catch {
    Write-Host "Корзина уже пуста или недоступна." -ForegroundColor Gray
}

Write-Host "=== Очистка завершена! ===" -ForegroundColor Cyan
Write-Host "Нажмите любую клавишу для выхода"
$null = [Console]::ReadKey($true)
exit