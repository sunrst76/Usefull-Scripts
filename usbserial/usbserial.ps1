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

# Функция получения пути для сохранения результатов
function Get-PathSearchResult {
    
    [CmdletBinding()]
    param(
    [string]$Title = "Сохранить результы как...",
    [string]$Filter = "TXT файлы (*.txt)|*.txt|Все файлы (*.*)|*.*",
    [string]$InitialDirectory = [Environment]::GetFolderPath("Desktop"),
    [string]$DefaultFileName = "USB_report_$(Get-Date -Format 'dd.MM.yyyy HH_mm_ss')")
    
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
    }
}

# находим диски usb
Set-WindowToForeground
$usbDrives = Get-CimInstance Win32_DiskDrive | Where-Object { $_.InterfaceType -eq "USB" }

if ($usbDrives) {
    $txtPath = Get-PathSearchResult
    $header = "=== НАЙДЕНЫ ПОДКЛЮЧЕННЫЕ USB-НАКОПИТЕЛИ === (Выгрузка: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss'))`n"
    Write-Host $header -ForegroundColor Green
    if ($txtPath -ne $null) {
        $header | Out-File -FilePath $txtPath -Encoding utf8 -Append
    }

    foreach ($drive in $usbDrives) {
        # извлекаем серийный номер (очищаем от лишних системных пробелов)
        $serial = $drive.SerialNumber.Trim()
        $size = [Math]::Round($drive.Size / 1GB, 2)
        
        # парсим  VID и PID из строки PNPDeviceID с помощью регулярных выражений
        $vid = "Не определен"
        $prodID = "Не определен"

        # переходим к системной ветке реестра, где гарантировано содержатся аппаратные VID/PID
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB"
        if (Test-Path $regPath){
            # ищем подпапки, в названии которых гарантированно содержатся аппаратные VID/PID
            $subKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue

            foreach ($key in $subKeys) {
                # проверяем, зарегистрирован ли текущий серийный номер флешки внутри этой папки VID/PID
                if (Test-Path (Join-Path $key.PSPath $serial) -ErrorAction SilentlyContinue) {
                    $folderName = $key.PSChildName # получаем строку вида "VID_07861&PID_5567"

                    # аккуратно вытаскиваем чистые 4 знака для VID и PID
                    if ($folderName -match "VID_([0-9A-Fa-f]{4})") { $vid = $Matches[1] }
                    if ($folderName -match "PID_([0-9A-Fa-f]{4})") { $prodID = $Matches[1] }
                    break
                }
            }
        }
        # если в ветке USB не нашли (такое бывает из-за кэша), проверяем соседнюю железную ветку USBSTOR
        if ($vid -eq "Не определен") {
            $regPathStor = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR"
            $subKeysStor = Get-ChildItem -Path $regPathStor -ErrorAction SilentlyContinue
             foreach ($key in $subKeysStor) {
                if ($key.PSChildName -match "VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})") {
                    # проверяем, зарегистрирован ли текущий серийный номер флешки внутри этой папки VID/PID
                    if (Test-Path (Join-Path $key.PSPath $serial) -ErrorAction SilentlyContinue) {
                        $vid = $Matches[1]
                        $prodID = $Matches[2]
                        break
                    }
                }
            }
        }        

# формируем структурированный текстовый блок 
$outputBlock = @"
Модель: $($drive.Model)
-> Серийный номер: $serial
-> Vendor ID (VID): $vid
-> Product ID (PID): $prodID
-> Объем диска: $size ГБ
"@

        # выводим информацию на экран
        Write-Host "Модель: $($drive.Model)" -ForegroundColor Cyan
        Write-Host " -> Серийный номер: $serial"
        Write-Host " -> Vendor ID (VID): $vid"
        Write-Host " -> Product ID (PID): $prodID"
        Write-Host " -> Объем диска: $size ГБ"
        Write-Host "-----------------------------------------------"

        if ($txtPath -ne $null) {
            $outputBlock | Out-File -FilePath $txtPath -Encoding utf8 -Append
            Write-Host "`n[!] Отчет успешно сформирован в файл:" -ForegroundColor Yellow
            Write-Host $txtPath -ForegroundColor White
        } else {
        Write-Host "Вывод в файл отменен" -ForegroundColor Red
            
        }
    }
} else {
    Write-Host "USB-Носители не найдены"
}
Set-WindowToForeground
Write-Host "Нажмите любую клавишу для выхода"
$null = [Console]::ReadKey($true)