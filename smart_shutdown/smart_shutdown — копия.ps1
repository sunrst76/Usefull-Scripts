Write-Host "=== Автовыключение ПК по завершении программы ===" -ForegroundColor Cyan
Write-Host "Получение списка активных процессов..." -ForegroundColor Gray

# 1. Запрос фильтра у пользователя для поиска среди всех процессов
Write-Host "Введите чатсь названия программы для поиска (например: explorer, chrome, svchost) или нажмите ENTER для вывода ВСЕХ:" -ForegroundColor Gray
$Filter = Read-Host "Фильтр/Поиск"

Write-Host "`nСбор данных из памяти ядра Windows..." -ForegroundColor Gray

# Получаем список запущенных процессов
if ([string]::IsNullOrWhiteSpace($Filter)) {
    $ActiveProcesses = Get-Process | Sort-Object Name
    Write-Host "Режим: Вывод всех системных и пользовательских процессов." -ForegroundColor Gray
} else {
    $ActiveProcesses = Get-Process | Where-Object { $_.Name -like "*$Filter*" } | Sort-Object Name
    Write-Host "Режим: Фильтр по слову '$Filter'." -ForegroundColor Gray
}

if ($ActiveProcesses.Count -eq 0) {
    Write-Host "Не найдено активных процессов." -ForegroundColor Blue
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
}

Write-Host "`nСписок процессов в системе :" -ForegroundColor Yellow
Write-Host "---------------------------------------------------" -ForegroundColor Gray


# Выводим процессы списком для удобного выбора
$ID = 1
$ProcessMenu = @{}

foreach ($Proc in $ActiveProcesses) {
    # Получаем описание процесса (для системных процессов Windows это очень полезно)
    $Description = ""
    try {
        if ($Proc.Description) { $Description = " - $($Proc.Description)" }
    } catch {}

    Write-Host "[$ID] " -NoNewline -ForegroundColor Yellow
    Write-Host "$($Proc.Name).exe " -NoNewline -ForegroundColor White -Bold
    Write-Host " (PID: $($Proc.ID))$Description" -ForegroundColor Gray

    # Добавляем в меню уникальное системное имя
    if (-not $ProcessMenu.ContainsValue($Proc.Name)) {
        $ProcessMenu.Add($ID, $Proc.Name)
        $ID++
    }
}

Write-Host "--------------------------------------------------------------------------" -ForegroundColor Gray
Write-Host ""
$UserChoice = Read-Host "Введите номер [ID] программы, за которой нужно следить"

if (-not $UserChoice -or -not $ProcessMenu.ContainsKey([int]$UserChoice)) {
    Write-Host "Неверный выбор. Скрипт завершен." -ForegroundColor Red
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
}

$TargetProcessName = $ProcessMenu[[int]$UserChoice]
Write-Host "`n[ Радар запущен ] Слежу за процессом: $TargetProcessName.exe" -ForegroundColor Green
Write-Host "Компьютер выключится аватоматически после закрытия этой программы." -ForegroundColor Yellow
Write-Host "Для отмены работы скрипта просто закройте это окно PowerShell." -ForegroundColor Gray

# Цикл мониторинга процесса
while ($true) {
    # Ищем процесс в памяти
    $CheckProcess = Get-Process -Name $TargetProcessName -ErrorAction SilentlyContinue

    # Если процесс больше не найден 
    if (-not $CheckProcess) {
        Write-Host "`n[ Внимание ] Процесс $TargetProcessName завершил работу!" -ForegroundColor Blue
        Write-Host "Выключение компьютера произойдет через 60 секунд." -ForegroundColor Red

        # Запускаем системный таймер выключения (у пользователя будет 60 секунд, чтобы отменить его командой shutdown /a)
        shutdown.exe /s /t 60 /c "Скрипт PowerShell: Целевой процесс завершен. Выключение системы."
        break
    }

    # Проверяем процесс раз в 30 секунд, чтобы не нагружать процессор
    Start-Sleep -Seconds 30
}
Write-Host "`nСкрипт выполнил задачу и закрывается" -ForegroundColor Gray
Write-Host "Нажмите любую клавишу для выхода"
$null = [Console]::ReadKey($true)
exit