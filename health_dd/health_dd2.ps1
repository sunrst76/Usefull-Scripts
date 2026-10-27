Write-Host "=== Проверка здоровья накопителей ===" -ForegroundColor Cyan
Write-Host "Сбор информации из системы..." -ForegroundColor Gray
Write-Host ""

# 1. Получаем список всех физических дисков 
$Disks = Get-WmiObject -Namespace "root\cimv2" -Class Win32_DiskDrive

if (-not $Disks) {
    Write-Host "Не удалось получить данные о дисках. Запустите скрипт от имени Администратора" -ForegroundColor Red
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
}

foreach ($Disk in $Disks) {
    
    # Красивый вывод основной информации
    Write-Host "Диск №$($Disk.Index): $($Disk.Model)" -ForegroundColor White -Bold
    Write-Host "-------------------------------------------------------------" -ForegroundColor Gray
    Write-Host " Размер:         $([Math]::Round($Disk.Size / 1Gb, 2)) ГБ"
    
    # Проверка статуса SMART
    $SmartStatus = $Disk.Status
    $StatusColor = "Green"
    if ($SmartStatus -ne "OK") { $StatusColor = "Red" }
    Write-Host " Статус диска:    " -NoNewline
    Write-Host "$SmartStatus" -ForegroundColor $StatusColor

    # 2. Глубокий опрос здоровья ячеек памяти и температуры через драйвер хранения            
    try {
        $PredictFailure = Get-WmiObject -Namespace "root\wmi" -Class MSStorageDriver_FailurePredictStatus -Filter "InstanceName LIKE '%$($Disk.SerialNumber.Trim())%'" -ErrorAction SilentlyContinue
        #Write-Host $PredictFailure
        if ($PredictFailure) {
            Write-Host "  Угроза сбоя:      " -NoNewline
            if ($PredictFailure.PredictFailure) {
                Write-Host "ДА (Диск умирает!)" -ForegroundColor Red
            } else {
                Write-Host "НЕТ (Ошибок нет)" -ForegroundColor Green
            }
        } else {
            Write-Host "Get-WmiObject не работает и переменная $PredictFailure не определена"
        }

        # Запрашиваем температуру на низком уровне
        $StorageTemp = Get-WmiObject -Namespace "root\wmi" -Class MSStorageDriver_ATAPISmartData -Filter "InstanceName LIKE '%$($Disk.SerialNumber.Trim())%'" -ErrorAction SilentlyContinue
        
        if ($StorageTemp -and $StorageTemp.VendorSpecific) {
            # Парсим 194-й или 190-й атрибут SMART (стандарт для температуры дисков)
            $Data = $StorageTemp.VendorSpecific
            $Temp = $null
            for ($i = 2; $i -lt $Data.Length; $i +=12) {
                if ($Data[$i] -eq 194 -or ($Data[$i] -eq 190)) {
                    $Temp = $Data[$i + 5]
                    break
                } 
            }

            if ($Temp -and $Temp -gt 0 -and $Temp -lt 100) {
                $TempColor = "Green"
                if ($Temp -gt 60) { $TempColor = "Red" }
                elseif ($Temp -gt 45) { $TempColor = "Yellow" }

                # Используем безопасное написание знака градуса
                Write-Host " Температура:     " -NoNewline
                Write-Host "$Temp$([char]0x00B0)C" -ForegroundColor $TempColor
            }
        } else {
            Write-Host "Get-WmiObject не работает и переменная $StorageTemp не определена"
        }

                
    } catch {
        Write-Host "Дополнительные датчики не ответили" -ForegroundColor Gray
    }
    Write-Host "" # Пустая строка между дисками
}

Write-Host "=== Проверка завершена ===" -ForegroundColor Cyan
Write-Host "Нажмите любую клавишу для выхода" -ForegroundColor Gray
$null = [Console]::ReadKey($true)
exit