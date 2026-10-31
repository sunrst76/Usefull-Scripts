$src = "с:\updates"  # путь к источнику
$dst = "d:\updates"   # путь к назначению

# Проверка существования исходной папки
if (!(Test-Path $src)) {
	Write-Host "Ошибка: Исходная папка не найдена по пути: $src" -ForegroundColor Red
	exit
}
# Проверка существования папки назначения
if (!(Test-Path $dst)) {
	Write-Host "Ошибка: Целевая папка не найдена по пути: $dst" -ForegroundColor Red
	#exit
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Write-Host "OK: создана новая целевая папка по пути: $dst" -ForegroundColor Green
}

# Быстро считаем общее количество файлов в источнике для ориентира
Write-Host "Анализ исходных файлов..." -ForegroundColor Cyan
$totalFiles = (Get-ChildItem -Path $src -Recurse -File).Count
Write-Host "Всего файлов для проверки: $totalFiles" -ForegroundColor Gray

Write-Host "Синхронизация файлов запущена..." -ForegroundColor Cyan
$processedFiles = 0
$SummaryLog = [System.Collections.Generic.List[string]]::new()
$isSummaryStarted = $false

& robocopy $src $dst /MIR /MT:24 /256 /R:1 /W:2 /NP | ForEach-Object {
    $line = $_.Trim()

    if ($line -match '^(Total|Copied|Skipped|Dirs\s*:|Папки\s*:)') {
        $isSummaryStarted = $true
    }

    if ($isSummaryStarted) {
        # Если началась статистика, сохраняем её строки для финала
        $null = $SummaryLog.Add($_)
    } elseif ($line -and $line.Length -gt 5 -and -not ($line -match 'Mismatch|FAILED|Extras|Bytes|Times|Started|Ended|ДОПОЛНИТ|EXTRA')) {
        $processedFiles++

        if ($processedFiles % 10 -eq 0 -or $processedFiles -eq $totalFiles) {
            # Считаем примерный процент
            $percent = [math]::Round(($processedFiles / $totalFiles) * 100)
            if ($percent -gt 100) { $percent = 100 }
        
            Write-Progress -Activity "Синхронизация файлов" `
                           -Status "Копирование и проверка файлов..." `
                           -PercentComplete $percent `
                           -CurrentOperation "Обработано: $processedFiles из $totalFiles ($percent%)"
        }
    }
}
    
Write-Progress -Activity "Синхронизация файлов" -Completed

Write-Host "`n[УСПЕХ] Синхронизация файлов завершена" -ForegroundColor Green
Write-Host "`n=== ИТОГОВАЯ СТАТИСТИКА СИНХРОНИЗАЦИИ ===" -ForegroundColor Yellow

foreach ($logline in $SummaryLog) {
    Write-Host $logline
}