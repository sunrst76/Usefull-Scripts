$src = "\\s75kav05.region.cbr.ru\klshare\Updates"  # путь к источнику
$dst = "d:\updates"   # путь к назначению

# Инициализация счетчиков статистики
$copiedFilesCount = 0
$skippedFilesCount = 0
$deletedItemsCount = 0

# Проверка существования исходной папки
if (!(Test-Path $src)) {
	Write-Host "Ошибка: Исходная папка не найдена по пути: $src" -ForegroundColor Red
	exit
}
# Проверка существования папки назначения
if (!(Test-Path $dst)) {
	Write-Host "Ошибка: Исходная папка не найдена по пути: $dst" -ForegroundColor Red
	exit
}

Write-Host "Сканирование файлов и расчет объема..." -ForegroundColor Cyan
$files = Get-ChildItem $src -Recurse -File -ErrorAction SilentlyContinue
$totalSize = ($files | Measure-Object -Property Length -Sum).Sum

$copiedSize = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Получаем ширину окна консоли (минус 1 символ для безопасности)
$bufferWidth = $Host.UI.RawUI.BufferSize.Width - 1

# Находим все пустые папки в источнике
$sourceDirs = Get-ChildItem $src -Directory -Recurse

foreach ($dir in $sourceDirs) {
    # Формируем путь для этой папки в назначении
    $relativeDirPath = $dir.FullName.Substring($src.Length)
    $targetDirPath = Join-Path $dst $relativeDirPath

    # Если папки в назначении нет, создаем ее
    if (!(Test-Path $targetDirPath)) {
        New-Item -ItemType Directory -Path $targetDirPath -Force | Out-Null
    }
}

foreach ($file in $files) {
    $relPath = $file.FullName.Substring($src.Length)
    $destFile = Join-Path $dst $relPath
    $destDir = Split-Path $destFile

    try {
        $shouldCopy = $true
        if (Test-Path $destFile) {
            $destFileInfo = Get-Item $destFile
            if ($file.LastWriteTime -le $destFileInfo.LastWriteTime) {
                $shouldCopy = $false
            }
        }

        if ($shouldCopy) {
            if (!(Test-Path $destDir)) { $null = New-Item -ItemType Directory -Force -Path $destDir }
            Copy-Item $file.FullName -Destination $destFile -Force -ErrorAction Stop
            $actionStatus = "Copy"
            $copiedFilesCount++
        } else {
            $actionStatus = "Skip"
            $skippedFilesCount++
        }
    } catch {
        $actionStatus = "Error"
    }

    # Расчет процентов и метрик
    $copiedSize += $file.Length
    $pct = [int](($copiedSize / $totalSize) * 100)

    $elapsedSec = $sw.Elapsed.TotalSeconds
    if ($elapsedSec -gt 0) {
        $speedMB = [math]::Round((($copiedSize / 1MB) / $elapsedSec), 2)
        $remainingBytes = $totalSize - $copiedSize
        $remainingSec = [math]::Round(($remainingBytes / ($copiedSize / $elapsedSec)), 0)
        $eta = [TimeSpan]::FromSeconds($remainingSec).ToString("hh\:mm\:ss")
    } else {
        $speedMB = 0
        $eta = "00:00:00"
    }

    # Классическая шкала из символов '#' и '-'
    $barLength = 15
    $filledLength = [int](($pct / 100) * $barLength)
    $unfilledLength = $barLength - $filledLength
    $progressBar = ("#" * $filledLength) + ("-" * $unfilledLength)

    # Сборка строки
    $formatTemplate = "[ {0} ] {1}% | MB/s: {2} | ETA: {3} | {4} -> {5}"
    $statusStr = $formatTemplate -f $progressBar, $pct, $speedMB, $eta, $actionStatus, $file.Name

    # Обрезка под ширину экрана
    if ($statusStr.Length -ge $bufferWidth) {
        $statusStr = $statusStr.Substring(0, $bufferWidth - 3) + "..."
    } else {
        $statusStr = $statusStr.PadRight($bufferWidth, " ")
    }

    # Вывод строки с возвратом каретки
    $carriageReturn = [char]13
    Write-Host -NoNewline "${carriageReturn}${statusStr}"
}

# --- БЛОК ОЧИСТКИ И УДАЛЕНИЯ ---
$spaces = " " * $bufferWidth
$carriageReturn = [char]13
Write-Host -NoNewline "${carriageReturn}${spaces}${carriageReturn}"

Write-Host "Очистка удаленных файлов в целевой папке..." -ForegroundColor Cyan

# ИСПРАВЛЕНО: Сортировка по убыванию длины пути предотвращает ошибки удаления родительских папок
$destItems = Get-ChildItem $dst -Recurse | Sort-Object {$_.FullName.Length} -Descending

foreach ($item in $destItems) {
    $relativeItemPath = $item.FullName.Substring($dst.Length)
    $sourceItemPath = Join-Path $src $relativeItemPath

    if (!(Test-Path $sourceItemPath)) {
        try {
            Remove-Item $item.FullName -Recurse -Force -ErrorAction Stop
            $deletedItemsCount++
        }
        catch {
            # Подавляем ложные предупреждения, если объект уже удален вместе с родителем
        }
    }
}

$sw.Stop()

# Финальная очистка строки прогресса
Write-Host -NoNewline "${carriageReturn}${spaces}${carriageReturn}"

# --- ВЫВОД ИТОГОВОЙ СТАТИСТИКИ ---
$finalTime = $sw.Elapsed.ToString('hh\:mm\:ss')
Write-Host "Синхронизация успешно завершена за ${finalTime}!" -ForegroundColor Green
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "Скопировано/обновлено файлов : $copiedFilesCount" -ForegroundColor Green
Write-Host "Пропущено (актуальные)      : $skippedFilesCount" -ForegroundColor Gray
Write-Host "Удалено устаревших объектов  : $deletedItemsCount" -ForegroundColor DarkYellow
Write-Host "----------------------------------------" -ForegroundColor Gray