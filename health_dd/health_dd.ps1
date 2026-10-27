Write-Host "=== Проверка здоровья накопителей ===" -ForegroundColor Cyan
Write-Host "Сбор информации из системы..." -ForegroundColor Gray
Write-Host ""

# Получаем список всех физических дисков 
$PhisicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

if (-not $PhisicalDisks) {
    Write-Host "Не удалось получить данные о дисках. Запустите скрипт от имени Администратора" -ForegroundColor Red
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
}

foreach ($Disk in $PhisicalDisks) {
    # Определение цвета для статуса здоровья 
    $HealthColor = "Green"
    if ($Disk.HealthStatus -ne "Healthy") { $HealthColor = "Red" }

    # Красивый вывод основной информации
    Write-Host "Диск №$($Disk.DeviceID): $($Disk.FriendlyName)" -ForegroundColor White
    Write-Host "--------------------------------------------------------"
    Write-Host " Тип накопителя: $($Disk.MediaType)"
    Write-Host " Размер:         $([Math]::Round($Disk.Size / 1Gb, 2)) ГБ"
    Write-Host " Статус здоровья: " -NoNewline
    Write-Host "$($Disk.HealthStatus)" -ForegroundColor $HealthColor
    Write-Host " Состояние шины: $($Disk.OperationalStatus)"

    # Дополнительняа глубокая диагностика для SSD / NVMe устройств
    # (Доступно, если накопитель поддерживает расширенный SMART через StorageCmdlets)
    try {
        $SmartData = Get-StorageReliabilityCounter -PhysicalDisk $Disk -ErrorAction SilentlyContinue
        if ($SmartData) {
            # Процент износа (актуально для SSD)
            if ($SmartData.Wear -ne $null) {
                $RemainingLife = 100 - $SmartData.Wear
                $LifeColor = "Green"
                if ($RemainingLife -lt 20) { $LifeColor = "Red" }
                elseif ($RemainingLife -lt 50) { $LifeColor = "Yellow" }

                Write-Host " Остаток ресурса: " -NoNewline
                Write-Host "$RemainingLife%" -ForegroundColor $LifeColor
            }
            
            # Температура (если датчик отдает данные)
            if ($SmartData.Temperature -gt 0) {
                $TempColor = "Green"
                if ($SmartData.Temperature -gt 65) { $TempColor = "Red" }
                elseif ($SmartData.Temperature -gt 50) { $TempColor = "Yellow" }

                Write-Host " Температура:     " -NoNewline
                Write-Host "$($SmartData.Temperature)°C" -ForegroundColor $TempColor
            }

            # Чтение критических предупреждений SMART
            if ($SmartData.ReadErrorsTotal -gt 0) {
                Write-Host " Ошибки чтения:    $($SmartData.ReadErrorsTotal)" -ForegroundColor Red
            }
        } else {
            Write-Host "Расширенный SMART $SmartData не поддерживается"
        }
    } catch {
        # Некоторые старые HDD не поддерживают командлет Get-StorageReliabilityCounter
        Write-Host "Глубокая диагностика не поддерживается" -ForegroundColor Red
    }
    Write-Host "" # Пустая строка между дисками
}

Write-Host "=== Проверка завершена ===" -ForegroundColor Cyan
Write-Host "Нажмите любую клавишу для выхода" -ForegroundColor Gray
$null = [Console]::ReadKey($true)
exit