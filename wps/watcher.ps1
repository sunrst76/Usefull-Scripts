Write-Host "Мониторинг подключения диска D:\ запущен..." -ForegroundColor Cyan

$TargetDrive = "D:"
$IsMounted = $false

while ($true) {
    $DriveExists = Test-Path -Path "$TargetDrive\"

    if ($DriveExists -and -not $IsMounted) {
        # диск только что вставили
        Write-Host "Обнаружено подключение диска $TargetDrive !"-ForegroundColor Green
        $IsMounted = $true
        
        # код синхронизации баз
        $ScriptPathLinux = "D:\Updates_linuxCopy_alternate.cmd"
        $ScriptPathAPK = "D:\Updates_Copy_alternate.cmd"
        
        if (Test-Path $ScriptPathLinux) {
            Write-Host "Запуск скрипта синхронизации антивирусных баз ТСНР" -ForegroundColor Yellow
            Start-Process -FilePath $ScriptPathLinux
        } else {
            Write-Warning "Файл запуска по пути $ScriptPathLinux не найден."            
        }

        if (Test-Path $ScriptPathAPK) {
            Write-Host "Запуск скрипта синхронизации антивирусных баз АПК" -ForegroundColor Yellow
            Start-Process -FilePath $ScriptPathAPK
        } else {
            Write-Warning "Файл запуска по пути $ScriptPathAPK не найден."
        }

    } elseif (-not $DriveExists -and $IsMounted) {
        # сбрасываем флаг, когда флешку вытащили
        Write-Host "Диск $TargetDrive извлечен!"-ForegroundColor Red
        $IsMounted = $false
    }


    # опрос через 2 сек
    Start-Sleep 2
}