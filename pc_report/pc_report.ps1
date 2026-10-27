# Подгружаем графический интерфейс Windows
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

# Функция принудительного вывода консоли PowerShell на передний план
function Set-WindowToForeground {
    $code = @"
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
"@
    $type = Add-Type -MemberDefinition $code -Name "Win32ShowWindow" -Namespace "Win32" -PassThru
    $hwnd = [System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) {
        [void][Win32.Win32ShowWindow]::ShowWindow($hwnd, 9) 
        [void][Win32.Win32ShowWindow]::SetForegroundWindow($hwnd)
    }
}

# Функция получения пути для сохранения отчета
function Get-PathSearchResult {
    
    [CmdletBinding()]
    param(
    [string]$Title = "Сохранить отчет как...",
    [string]$Filter = "HTML файлы (*.html)|*.html|Все файлы (*.*)|*.*",
    [string]$InitialDirectory = [Environment]::GetFolderPath("Desktop"),
    [string]$DefaultFileName = "PC_Specification_Report.html")
    
    # Загружаем необходимую сборку для работы с графическим интерфейсом
    Add-Type -AssemblyName System.Windows.Forms
    

    # Создаем объект диалогового окна 
    $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveDialog.Title = $Title
    $SaveDialog.Filter = $Filter
    $SaveDialog.InitialDirectory = $InitialDirectory
    $SaveDialog.FileName = $DefaultFileName

    # Отображаем окно поверх всех остальных окон
    $TopMostForm = New-Object System.Windows.Forms.Form
    $TopMostForm.TopMost = $true

    # Показываем диалог
    $Result = $SaveDialog.ShowDialog($TopMostForm)

    # Если пользователь нажал ОК, возвращаем выбранный путь
    if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $SaveDialog.FileName
    } else {
        return $null
        Write-Host "Выпонена отмена выбора пути сохранения файла."
        Write-Host "Нажмите любую клавишу для выхода"
        $null = [Console]::ReadKey($true)
        exit
    }
}

Write-Host "=== Сбор характеристик компьютера ===" -ForegroundColor Cyan
Write-Host "Опрос оборудования... Это займет несколько секунд." -ForegroundColor Gray

# 1. Безопасный сбор данных о железе с защитой от сбоев
try { $OS = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch { $OS = $null }
try { $CPU = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop } catch { $CPU = $null }
try { $MB = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop } catch { $MB = $null }
try { $GPU = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop } catch { $GPU = $null }
try { $Disks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop } catch { $Disks = $null }
try { $Networks = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -eq $true } } catch { $Networks = @() }

# Подсчет оперативной памяти
try {
    $RAM_Modules = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue
    Write-Host $RAM_Modules
    if ($RAM_Modules) {
        $TotalRAM = 0
        foreach ($Module in $RAM_Modules) { $TotalRAM += $Module.Capacity }
        $TotalRAM_GB = [Math]::Round($TotalRAM / 1GB, 0)
        $RAM_Count = @($RAM_Modules).Count
    } else {
        $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        $TotalRAM_GB = [Math]::Round($ComputerSystem.TotalPhysicalMemory / 1GB, 0)
        $RAM_Count = "Определено системой"
    }
} catch {
    $TotalRAM_GB = "Не определено"
    $RAM_Count = "0"
}

# 2. Формирование адаптивной HTML-страницы со стилями
$HtmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Характеристики ПК: $($OS.CSName)</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; background-color: #f0f2f5; color: #2c3e50; padding: 30px; margin: 0; }
        .container { max-width: 900px; margin: 0 auto; background: #ffffff; padding: 40px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 15px; margin-top: 0; font-weight: 400; }
        h2 { color: #5c5c5c; font-size: 1.3em; margin-top: 30px; margin-bottom: 10px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }
        .meta { font-size: 0.9em; color: #888888; margin-bottom: 30px; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 10px; background: #ffffff; }
        th, td { padding: 14px 16px; text-align: left; border-bottom: 1px solid #eef2f5; font-size: 0.95em; }
        th { background-color: #f8f9fa; }
        .footer { font-size: 0.8em; text-align: center; color: #aaaaaa; margin-top: 40px; border-top: 1px solid #eee; padding-top: 15px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Технический отчет о системе: $($OS.CSName)</h1>
        <div class="meta">Дата сборки данных: $(Get-Date -Format "dd.MM.yyyy HH:mm:ss")</div>

        <h2>Операционная система</h2>
        <table>
            <tr><th>Название системы</th><td>$($OS.Caption)</td></tr>
            <tr><th>Архитектура / Версия</th><td>$($OS.OSArchitecture) (Сборка $($OS.Version))</td></tr>
            <tr><th>Системная папка</th><td>$($OS.WindowsDirectory)</td></tr>
        </table>

        <h2>Материнская плата</h2>
        <table>
            <tr><th>Производитель</th><td>$($MB.Manufacturer)</td></tr>
            <tr><th>Модель платы</th><td>$($MB.Product)</td></tr>            
        </table>

        <h2>Процессор (CPU)</h2>
        <table>
            <tr><th>Модель ЦП</th><td>$($CPU.Name)</td></tr>
            <tr><th>Ядра / Потоки</th><td>Физических ядер: $($CPU.NumberOfCores) | Логических потоков: $($CPU.NumberOfLogicalProcessors)</td></tr>
            <tr><th>Базовая частота</th><td>$([Math]::Round($CPU.CurrentClockSpeed / 1000, 2)) ГГЦ</td></tr>
        </table>

        <h2>Оперативная память (RAM)</h2>
        <table>
            <tr><th>Общий объем</th><td>$TotalRAM_GB ГБ</td></tr>
            <tr><th>Установлено планок</th><td>$RAM_Count шт.</td></tr>
        </table>

        <h2>Видеокарта (GPU)</h2>
        <table>
            <tr><th>Название видеочипа</th><td>$($GPU.Name)</td></tr>
            <tr><th>Версия видеодрайвера</th><td>$($GPU.DriverVersion)</td></tr>
            <tr><th>Текущее разрешение</th><td>$($GPU.CurrentHorizontalResolution) x $($GPU.CurrentVerticalResolution) пикселей</td></tr>
        </table>

        <h2>Дисковые накопители</h2>
        <table>
                    
"@

# Заполнение таблицы дисков
if ($Disks) {
    $DiskID = 1
    foreach ($Disk in $Disks) {
        $DiskSize = [Math]::Round($Disk.Size / 1GB, 2)
        $HtmlContent += "<tr><th>Физический диск №$DiskID</th><td>$($Disk.Model) - <strong>$DiskSize ГБ</strong></td></tr>"
        $DiskID++
    }
} else {
    $HtmlContent += "<tr><th>Диски</th><td>Не удалось прочитать параметры накопителей</td></tr>"
}

$HtmlContent += @"
    </table>

    <h2>Сетевые интерфейсы</h2>
    <table>
"@

# Заполнение таблицы сетевых карт

if ($NetWorks) {    
    foreach ($Net in $NetWorks) {
        $HtmlContent += "<tr><th>$($Net.NetConnectionID)</th><td>$($Net.Name) (MAC: $($Net.MACAddress))</td></tr>"
    }
} else {
    $HtmlContent += "<tr><th>Сеть</th><td>Активные сетевые адаптеры не найдены</td></tr>"
}

# Закрытие структуры HTML документа
$HtmlContent += @"
    </table>
    <div class="footer">Отчет сгенерирован автоматически скриптом PowerShell. Файл сохранен по пути: $HtmlPath.</div>
  </div>
</body>
</html>
"@

# Путь для сохранения отчета
$HtmlPath = Get-PathSearchResult

if ($HtmlPath -ne $null) {
    # Запись файла в кодировке UTF-8 и немедленное открытие
    Out-File -FilePath $HtmlPath -InputObject $HtmlContent -Encoding utf8
}

Set-WindowToForeground

Write-Host "`n==============================================" -ForegroundColor Yellow
Write-Host "В каком формате сохранить отчет?" -ForegroundColor Yellow
Write-Host "1. Открыть как веб-страницу (HTML)"
Write-Host "2. Сгенерировать и сохранить документ (PDF)"
$FormatChoice = Read-Host "Введите номер действия (1 или 2)"

if ($FormatChoice -eq "2") {
    # Режим PDF
    $UserSavePath = Get-PathSearchResult -Filter "PDF файлы (*.pdf)|*.pdf" -DefaultFileName "PC_Specification_Report.pdf"
    
    if ($UserSavePath) {
        Write-Host "`nКонвертация отчета в PDF..." -ForegroundColor Yellow
        $EdgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

        if (Test-Path $EdgePath) {
            $Arguments = @(
                "--headless",
                "--disable-gpu",
                "--run-all-compositor-stages-before-draw",
                "--print-to-pdf=`"$UserSavePath`"",
                "`"$HtmlPath`""
            )
            Start-Process -FilePath $EdgePath -ArgumentList $Arguments -Wait -NoNewWindow

            if (Test-Path $UserSavePath) {
                Write-Host "[ Успех ] PDF-отчет успешно сохранен!" -ForegroundColor Green
                Invoke-Item -Path $UserSavePath
            } else {
                Write-Host "Ошибка генерации PDF. Открываю HTML..." -ForegroundColor Green
                Invoke-Item -Path $HtmlPath
            }
        } else {
            Write-Host "Браузер Edge не найден для конвертации. Открываю HTML..." -ForegroundColor Green
            Invoke-Item -Path $HtmlPath
        }
    }
} else {
    if ($HtmlPath -ne $null) {
        # Режим HTML
        Invoke-Item -Path $HtmlPath
        Write-Host "[ Успех ] Отчет успешно сформирован и открыт в браузере по-умолчанию!" -ForegroundColor Green
        Write-Host "Путь к файлу: $HtmlPath" -ForegroundColor Gray
    }
}
Set-WindowToForeground

Write-Host "Нажмите любую клавишу для выхода"
$null = [Console]::ReadKey($true)
exit