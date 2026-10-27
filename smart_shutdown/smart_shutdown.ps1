Write-Host "=== Автовыключение ПК по завершении программы ===" -ForegroundColor Cyan
Write-Host "Получение списка активных процессов..." -ForegroundColor Gray

# 1. Запрос фильтра у пользователя для поиска среди всех процессов
Write-Host "Введите чатсь названия программы для поиска (например: explorer, chrome, svchost) или нажмите ENTER для вывода ВСЕХ:" -ForegroundColor Gray
$Filter = Read-Host "Фильтр/Поиск"

Write-Host "`nСбор данных из памяти ядра Windows..." -ForegroundColor Gray

# Получаем список запущенных процессов
if ([string]::IsNullOrWhiteSpace($Filter)) {
    $ActiveProcesses = Get-Process
    Write-Host "Режим: Вывод всех системных и пользовательских процессов." -ForegroundColor Gray
} else {
    $ActiveProcesses = Get-Process | Where-Object { $_.Name -like "*$Filter*" }
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

# Группируем процессы по имени, чтобы избавиться от дубликатов ID
$GroupedProcesses = $ActiveProcesses | Group-Object -Property Name | Sort-Object Name

# Выводим процессы списком для удобного выбора
$ID = 1
$ProcessMenu = @{}

foreach ($Group in $GroupedProcesses) {
    # Получаем описание процесса (для системных процессов Windows это очень полезно)
    $FirstProc = $Group.Group[0]
    $Description = ""
    try {
        if ($FirstProc.Description) { $Description = " - $($FirstProc.Description)" }
    } catch {}

    # Считаем количество запущенных копий (процессов) с этим именем
    $CountInfo = ""
    if ($Group.Count -gt 1) { $CountInfo = " [Копий в памяти: $($Group.Count)]" }

    Write-Host "[$ID] " -NoNewline -ForegroundColor Yellow
    Write-Host "$($Group.Name) " -NoNewline -ForegroundColor White -Bold
    Write-Host "$CountInfo$Description" -ForegroundColor Gray

    # Добавляем в меню уникальное системное имя
    if (-not $ProcessMenu.ContainsValue($Proc.Name)) {
        $ProcessMenu.Add($ID, $Group.Name)
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
Write-Host "`n[ Радар запущен ] Слежу за процессом: $TargetProcessName" -ForegroundColor Green
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
    Start-Sleep -Seconds 20
}
Write-Host "`nСкрипт выполнил задачу и закрывается" -ForegroundColor Gray
Write-Host "Нажмите любую клавишу для выхода"
$null = [Console]::ReadKey($true)
exit