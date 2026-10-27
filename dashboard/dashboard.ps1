# --- Системный вызов для мгновенного скрытия окна консоли ---
$WinAPI = Add-Type -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

[DllImport("user32.dll")]
public static extern bool SetForegroundWindow(IntPtr hWnd);
"@ -Name "Win32ShowWindowAsync" -Namespace Win32Functions -PassThru

# Находим идентификатор (дескриптор) текущего черного окна и скрываем его (параметр 0)
[void]$WinAPI::ShowWindowAsync((Get-Process -Id $Pid).MainWindowHandle, 0)

<# Автоматический перезапуск от имени Администратора
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    # Перезапускаем этот же файл скрипта, но уже с правами админа (-Verb RunAs)
    Start-Process powershell.exe -ArgumentList "-Noprofile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit # Закрываем текущую неполноправную копию дашборда
}#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# Функция для выбора одной папки целиком
function Get-TargetFolder {
    param($Description)
    Set-WindowToForeground
    
    $Shell = New-Object -ComObject Shell.Application
    $Flags = 16 + 64 + 8
    
    $Folder = $Shell.BrowseForFolder(0, $Description, $Flags, 0)
    if ($Folder) { return $Folder.Self.Path }
    return $null
}

# --- Создание главного окна ---
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "PowerShell Системный Дашборд"
$Form.Size = New-Object System.Drawing.Size(1100, 650)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedSingle"
$Form.MaximizeBox = $false

# --- Стили и шрифты ---
$FontTitle = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$FontButton = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
$FontLog = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Regular)

# Заголовок
$Label = New-Object System.Windows.Forms.Label
$Label.Text = "Панель управления системой"
$Label.Font = $FontTitle
$Label.Location = New-Object System.Drawing.Point(20, 15)
$Label.Size = New-Object System.Drawing.Size(400, 30)
$Form.Controls.Add($Label)

# --- Поле вывода информации (Лог) ---
$OutputBox = New-Object System.Windows.Forms.TextBox
$OutputBox.Multiline = $true
$OutputBox.ScrollBars = "Vertical"
$OutputBox.Font = $FontLog
$OutputBox.Location = New-Object System.Drawing.Point(20, 60)
$OutputBox.Size = New-Object System.Drawing.Size(650, 520)
$OutputBox.ReadOnly = $true
$OutputBox.BackColor = [System.Drawing.Color]::Black
$OutputBox.ForeColor =  [System.Drawing.Color]::LimeGreen
$OutputBox.Text = "Дашборд готов к работе.`r`nНажмите любую кнопку справа..."
$Form.Controls.Add($OutputBox)

# Функция для плавного вывода текста в лог
function Write-log ($Text) {
    $OutputBox.AppendText("`r`n`r`n$((Get-Date).ToString('HH:mm:ss'))$Text")
}

# --- Кнопка 1: Информация о ПК ---
$BtnInfo = New-Object System.Windows.Forms.Button
$BtnInfo.Text = "Статус системы"
$BtnInfo.Font = $FontButton
$BtnInfo.Location = New-Object System.Drawing.Point(700, 10)
$BtnInfo.Size = New-Object System.Drawing.Size(160, 40)

$BtnInfo.Add_Click({
    Write-log "`r`nСбор информации о системе..."
    $Os = Get-CimInstance Win32_OperatingSystem
    $Cs = Get-CimInstance Win32_ComputerSystem
    $Cpu = Get-CimInstance Win32_Processor
    $Disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"

    $FreeSpace = [Math]::Round(($Disk.FreeSpace / 1GB), 2)
    $TotalSpace = [Math]::Round(($Disk.Size / 1GB), 2)
    $TotalRam = [Math]::Round(($Cs.TotalPhysicalMemory / 1GB), 1)
    $UpTimeDays = ((Get-Date) - $Os.LastBootUpTime).Days
    
    $Res = " `r`n==== ОТЧЕТ О СИСТЕМЕ ====="
    $Res += " `r`nИмя ПК: $($Cs.Name)"
    $Res += " `r`nOC: $($Os.Caption) ($($Os.OSArchitecture))"
    $Res += " `r`nПроцессор: $($Cpu.Name)"
    $Res += " `r`nОперативная память (RAM): $TotalRam ГБ"
    $Res += " `r`nСвободно на С: $FreeSpace ГБ из $TotalSpace ГБ"
    $Res += " `r`nВремя непрерывной работы: $UpTimeDays дн."
    $Res += " `r`n=========================="
    Write-log $Res
})
$Form.Controls.Add($BtnInfo)

# --- Кнопка 2: Очистка Temp ---
$BtnClean = New-Object System.Windows.Forms.Button
$BtnClean.Text = "Очистить Temp"
$BtnClean.Font = $FontButton
$BtnClean.Location = New-Object System.Drawing.Point(700, 60)
$BtnClean.Size = New-Object System.Drawing.Size(160, 40)

$BtnClean.Add_Click({
    Write-log "`r`nЗапуск очистки временных файлов..."
    $TempPath = "C:\Users\$env:USERNAME\AppData\Local\Temp"
    $Files = Get-ChildItem $TempPath -File -Recurse -ErrorAction SilentlyContinue
    $Dirs = Get-ChildItem $TempPath -Recurse -ErrorAction SilentlyContinue
    $DeletedCount = 0
    
    # Сначала удалим только файлы, а не сразу папки с файлами, чтобы счетчик учитывал все элементы
    foreach ($File in $Files) {
        try {
            Remove-Item $File.FullName -Force -ErrorAction Stop
            $DeletedCount++
            
        } catch {}

    }
    # Затем удаляем папки
    foreach ($Dir in $Dirs) {
        try {
            Remove-Item $Dir.FullName -Force -Recurse -ErrorAction Stop
            $DeletedCount++
            
        } catch {}

    }
    Write-log "`r`nОчистка завершена. Удалено элементов: $DeletedCount"
})

$Form.Controls.Add($BtnClean)

# --- Кнопка 3: Перезапуск Диспетчера печати ---
$BtnSpooler = New-Object System.Windows.Forms.Button
$BtnSpooler.Text = "Сбросить печать"
$BtnSpooler.Font = $FontButton
$BtnSpooler.Location = New-Object System.Drawing.Point(700, 110)
$BtnSpooler.Size = New-Object System.Drawing.Size(160, 40)

$BtnSpooler.Add_Click({
    Write-log "`r`nПерезапуск службы Spooler..."
    try {
        Restart-Service -Name "Spooler" -Force -ErrorAction Stop
        Write-log "`r`nСлужба печати успешно перезапущена!"
    } catch { Write-log "`r`nОШИБКА: Запустите PowerShell от имени Администратора!" }
})

$Form.Controls.Add($BtnSpooler)

# --- Кнопка 4:Пинг ---
$BtnPing = New-Object System.Windows.Forms.Button
$BtnPing.Text = "Проверить сеть"
$BtnPing.Font = $FontButton
$BtnPing.Location = New-Object System.Drawing.Point(700, 160)
$BtnPing.Size = New-Object System.Drawing.Size(160, 40)

$BtnPing.Add_Click({
    Write-log "`r`nПроверка связи с cbrportal.cbr.ru..."
    $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True"
    $found = $false

    foreach ($adapter in $adapters) {
        # Проходим по всем IPv4 адресам этого адаптера
        for ($i = 0; $i -lt $adapter.IPAddress.Count; $i++) {
            $ip = $adapter.IPAddress[$i]

            # Фильтруем, чтобы выводить только IPv4 (исключаем IPv6, содержащие двоеточия)
            if ($ip -notlike "*:*") {
                # Берем маску подсети с тем же индексом, что и IP-адрес
                $mask = $adapter.IPSubnet[$i]
                $name = $adapter.Description

                Write-log "`r`nСетевая карта: $name -> IP-адрес: $ip -> Маска подсети: $mask"
                                
                if (Test-Connection -ComputerName "cbrportal.cbr.ru" -Count 2 -Quiet) {
                    Write-log "`r`nСвязь стабильна!"
                } else {
                    Write-log "`r`nОШИБКА: Сервер недоступен. Проверьте кабель!"
                }

                $found = $true
            }
        }
    }

    if (-not $found) {
        Write-log "`r`nАктивных сетевых подключений с IPv4-адресами не найдено."
    }
    
 <#   foreach ($Adapter in $IpInfo) {
        Write-log " `r`nСеть: $($Adapter.InterfaceAlias) -> IP: $($Adapter.IPAddress) -> Mask: $($Adapter.PrefixLength)"
    }    
    if (Test-Connection -ComputerName "cbrportal.cbr.ru" -Count 2 -Quiet) {
        Write-log "`r`nСвязь стабильна!"
    } else {
        Write-log "`r`nОШИБКА: Сервер недоступен. Проверьте кабель!"
    }#>
})
$Form.Controls.Add($BtnPing)

# --- Кнопка 5: Очистка сетевого кэша (DNS) ---
$BtnDNS = New-Object System.Windows.Forms.Button
$BtnDNS.Text = "Сбросить DNS кэш"
$BtnDNS.Font = $FontButton
$BtnDNS.Location = New-Object System.Drawing.Point(700, 210)
$BtnDNS.Size = New-Object System.Drawing.Size(160, 40)

$BtnDNS.Add_Click({
    Clear-DnsClientCache
    Write-log " `r`nСетевой кэш DNS успешно очищен!"
})
$Form.Controls.Add($BtnDNS)

# --- Кнопка 6: Мониторинг ресурсов и процессов ---
$BtnRAM = New-Object System.Windows.Forms.Button
$BtnRAM.Text = "Топ процессов (ОЗУ)"
$BtnRAM.Font = $FontButton
$BtnRAM.Location = New-Object System.Drawing.Point(700, 260)
$BtnRAM.Size = New-Object System.Drawing.Size(160, 40)

$BtnRAM.Add_Click({
    $InputProcess = [Microsoft.VisualBasic.Interaction]::InputBox("Введите часть названия программы для поиска (например: explorer, chrome, svchost), введите число самых требовательных процессов для вывода в лог или нажмите ENTER для вывода ВСЕХ:", "Вывод процессов", " ")
    $NumberProcess = 0

    if ($InputProcess -eq "") {
        return
    } elseif ($InputProcess -eq " ") {
        $ActiveProcesses = Get-Process | Sort-Object WorkingSet -Descending
        Write-log "`r`nРежим: Вывод всех системных и пользовательских процессов."        
    } elseif ([int]::TryParse($InputProcess, [ref]$NumberProcess)) {
        $ActiveProcesses = Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First $InputProcess
        Write-log "`r`nРежим: Вывод $NumberProcess самых требовательных системных и пользовательских процессов."
    } else {
        $ActiveProcesses = Get-Process | Where-Object { $_.Name -like "*$InputProcess*" }
        Write-log "`r`nРежим: Фильтр по слову '$InputProcess'."        
    }

    foreach ($p in $ActiveProcesses) {
            $Size = [Math]::Round($p.WorkingSet / 1MB, 0)
            Write-log "`r`nПрограмма: $($p.ProcessName) -> Потребляет: $Size МБ"
    }
})
$Form.Controls.Add($BtnRAM)

# --- Кнопка 7: Завершить процесс ---
$BtnKillProc = New-Object System.Windows.Forms.Button
$BtnKillProc.Text = "Завершить процесс"
$BtnKillProc.Font = $FontButton
$BtnKillProc.Location = New-Object System.Drawing.Point(700, 310)
$BtnKillProc.Size = New-Object System.Drawing.Size(160, 40)

$BtnKillProc.Add_Click({
    $ProcName = [Microsoft.VisualBasic.Interaction]::InputBox("Введите точное имя процесса для завершения (например: explorer, chrome, svchost):", "Завершить процесс", "")
    if (-not [string]::IsNullOrWhiteSpace($ProcName)) {
        Write-log "`r`nПопытка остановить процесс: $ProcName..."
        if (Get-Process -Name $ProcName -ErrorAction SilentlyContinue) {
            Stop-Process -Name $ProcName -Force
            Write-log "`r`nВсе процессы: '$ProcName' были принудительно завершены."
        } else {
            Write-log "`r`nПроцесс с именем '$ProcName' сейчас не запущен."
        }
    }
})
$Form.Controls.Add($BtnKillProc)

# --- Кнопка 8: Системные твики и утилиты ---
$BtnGodMode = New-Object System.Windows.Forms.Button
$BtnGodMode.Text = "Включить God Mode"
$BtnGodMode.Font = $FontButton
$BtnGodMode.Location = New-Object System.Drawing.Point(700, 360)
$BtnGodMode.Size = New-Object System.Drawing.Size(160, 40)

$BtnGodMode.Add_Click({
    $Path = "$env:USERPROFILE\Desktop\GodeMode.{ED7BA470-8E54-465E-825C-99712043E01C}"
    if (-not [System.IO.Directory]::Exists($Path)) {
        [void][System.IO.Directory]::CreateDirectory($Path)
        #New-Item -Path $Path -ItemType Directory | Out-Null
        $Shell = New-Object -ComObject Shell.Application
        $Shell.Namespace(0).Self.InvokeVerb("Refresh")
        Write-log "`r`nПапка 'God Mode' успешно создана на вашем Рабочем столе!"
    } else {
        Write-log "`r`nПапка 'God Mode' уже существует на Рабочем столе."
    }

})
$Form.Controls.Add($BtnGodMode)

# --- Кнопка 9: Быстрое сканирование диска ---
$BtnSFC = New-Object System.Windows.Forms.Button
$BtnSFC.Text = "Проверить файлы системы"
$BtnSFC.Font = $FontButton
$BtnSFC.Location = New-Object System.Drawing.Point(700, 410)
$BtnSFC.Size = New-Object System.Drawing.Size(160, 40)

$BtnSFC.Add_Click({
    Write-log "`r`nЗапуск быстрой проверки системных файлов..."
    try {
        sfc /verifyonly
        Write-log "`r`nПроверка запущена! Результаты будут записаны в системный журнал CBS.log."
    } catch {
        Write-log "`r`nОШИБКА: Требуются права Администратора."
    }
})
$Form.Controls.Add($BtnSFC)

# --- Кнопка 10: Просмотр системного журнала CBS.log ---
$BtnCBS = New-Object System.Windows.Forms.Button
$BtnCBS.Text = "Просмотреть CBS.log"
$BtnCBS.Font = $FontButton
$BtnCBS.Location = New-Object System.Drawing.Point(700, 460)
$BtnCBS.Size = New-Object System.Drawing.Size(160, 40)
$BtnCBS.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

$BtnCBS.Add_Click({
    Write-log "`r`nЧтение и фильтрация CBS.log на Рабочий стол..."
    
    $LogPath = "C:\Windows\Logs\CBS\CBS.log"
    $OutputPath = "$env:USERPROFILE\Desktop\sfc_report.txt"

    if (Test-Path $LogPath) {
        try {
            # Вытягиваем только строки проверки файлов [R] и сохраняем в файл
            Get-Content $LogPath -ErrorAction Stop |
                Select-String -Pattern "\[SR]\" |
                ForEach-Object { $_.Line } |
                Out-File $OutputPath -Encoding utf8

            Write-log "`r`nАнализ заверешен! Чистый отчет сохранен на вашем Рабочем столе в файл sfc_report.txt."
            # Автоматически открываем блокнот с отчетом для пользователя
            Start-Process notepad.exe $OutputPath
        } catch {
            Write-log "`r`nОШИБКА: Не удалось прочесть лог. Запустите дашборд от имени Администратора!"
        }
    } else {
        Write-log "`r`nФайл CBS.log не найден. Проверка SFC еще ни разу не запускалась."
    }
})
$Form.Controls.Add($BtnCBS)

# --- Кнопка 11: Извлечение сохраненных паролей Windows ---
$BtnCredentials = New-Object System.Windows.Forms.Button
$BtnCredentials.Text = " Пароли системы"
$BtnCredentials.Font = $FontButton
$BtnCredentials.Location = New-Object System.Drawing.Point(700, 510)
$BtnCredentials.Size = New-Object System.Drawing.Size(160, 40)
$BtnCredentials.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

$BtnCredentials.Add_Click({
    Write-log "`r`nСканирование Диспетчера учетных данных Windows..."

    # Способ 1: Получаем список сетевых паролей через cmdkey
    $CmdkeyOutput = cmdkey /list
    $Targets = $CmdkeyOutput | Select-String "Целевой объект:" | ForEach-Object { $_.Line.Split(":")[1].Trim() }

    if ($Targets) {
        Write-log "`r`n--- НАЙДЕНЫ СЕТЕВЫЕ УЧЕТНЫЕ ЗАПИСИ (cmdkey) ---"
        foreach ($T in $Targets) {
            Write-log "`r`nРесурс: $t"
        }
    }

    # Способ 2: Глубокое чтение системных сейфов Windows Vault (пароли приложений и веб-форм)
    try {
        # Подключаем тип из .NET сборки для работы с системными сейфами
        $VaultType = [Type]::GetType("System.Windows.Forms.Form") # Заглушка для загрузки базовых типов

        # PowerShell-скрипт для вызова внутренней библиотеки VaultCli.dll
        $Vaults = [Windows.Security.Credentials.PasswordVault, Windows.Security.Credentials, ContentType=WindowsRuntime]::new()
        $Creds = $Vaults.RetrieveAll()

        if ($Creds.Count -gt 0) {
            Write-log "`r`n--- СОХРАНЕННЫЕ ПАРОЛИ ПРИЛОЖЕНИЙ И ВЕБ-СЕЙФОВ ---"
            foreach ($C in $Creds) {
                # Заставляем сейф расшифровать пароль прямо в память
                $C.RetrievePassword()
                Write-log "`r`nРесурс: $($C.Resource) | Логин: $($C.UserName) | Пароль: $($C.Password)"
            }
        } else {
            Write-log "`r`nДополнительных паролей в Windows Vault не обнаружено."
        }
    } catch {
        Write-log "`r`nДля глубокого сканирования веб-сейфов требуются права Администратора."
    }
})

$Form.Controls.Add($BtnCredentials)

# --- Кнопка 12: Управление ПО и обновлениями---
$BtnUpdates = New-Object System.Windows.Forms.Button
$BtnUpdates.Text = "История обновлений"
$BtnUpdates.Font = $FontButton
$BtnUpdates.Location = New-Object System.Drawing.Point(880, 10)
$BtnUpdates.Size = New-Object System.Drawing.Size(160, 40)

$BtnUpdates.Add_Click({
    Write-log "`r`nЧтение истории обновлений..."
    $Updates = Get-CimInstance Win32_QuickFixEngineering | Sort-Object InstalledOn -Descending | Select-Object -First 5
    foreach ($U in $Updates) {
        Write-log "`r`nПатч: $($U.HotFixID) от $($U.InstalledOn.ToString('dd.MM.yyyy'))"
    }
})

$Form.Controls.Add($BtnUpdates)

# --- Кнопка 13: Список автозагрузки ---
$BtnStartUp = New-Object System.Windows.Forms.Button
$BtnStartUp.Text = "Список автозагрузки"
$BtnStartUp.Font = $FontButton
$BtnStartUp.Location = New-Object System.Drawing.Point(880, 60)
$BtnStartUp.Size = New-Object System.Drawing.Size(160, 40)

$BtnStartUp.Add_Click({
    Write-log "`r`nАнализ реестра автозагрузки..."
    $RegPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run"
    )

    $Global:StartupItems = @()
    $ID = 1

    # Собираем элементы из реестра
    foreach ($Path in $RegPaths) {
        if (Test-Path $Path) {
            $Properties = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
            foreach ($Prop in $Properties.PSObject.Properties) {
                # Исключаем системные свойства PowerShell
                if ($Prop.Name -notmatch "PSPath|PSParentPath|PSChildName|PSDrive|PSProvider") {
                    $Global:StartupItems += [PSCustomObject]@{
                        ID = $ID
                        Name = $Prop.Name
                        Value = $Prop.Value
                        Type = "Реестр ($($Path.Split('\')[-1]))"
                        Path = $Path
                    }
                    $ID++
                } 
            }
        }
    }

    # Собираем элементы из папки "Автозагрузка" пользователя
    $ShortcutFolder = [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs\Startup")
    if (Test-Path $ShortcutFolder) {
        $Files = Get-ChildItem -Path $ShortcutFolder -File
        foreach ($File in $Files) {
            $Global:StartupItems += [PSCustomObject]@{
                ID = $ID
                Name = $File.Name
                Value = $File.FullName
                Type = "Папка Автозагрузка"
                Path = $File.FullName
            }
            $ID++
        }
    }

    # Вывод на экран
    if ($Global:StartupItems.Count -eq 0) {
        Write-log "`r`nАвтозагрузка пуста! Никаких лишних программ не найдено."
    }

    # Форматируем вывод списком 
    foreach ($Item in $Global:StartupItems) {
        Write-log "`r`n[$($Item.ID)] Программа: $($Item.Name)`r`nТип: $($Item.Type)`r`nКоманда: $($Item.Value)"
    }
})

$Form.Controls.Add($BtnStartUp)

# --- Кнопка 14: Удаление программы из автозагрузки ---
$BtnRemoveStartup = New-Object System.Windows.Forms.Button
$BtnRemoveStartup.Text = "Удалить из автозагрузки"
$BtnRemoveStartup.Font = $FontButton
$BtnRemoveStartup.Location = New-Object System.Drawing.Point(880, 110)
$BtnRemoveStartup.Size = New-Object System.Drawing.Size(160, 40)

$BtnRemoveStartup.Add_Click({
    $InputID = [Microsoft.VisualBasic.Interaction]::InputBox("Введите номер [ID] программы для удаления из автозагрузки:", "Удаление автозагрузки", "")

    if ($InputID -match '^\d+$') {
        $TargetItem = $Global:StartupItems | Where-Object { $_.ID -eq [int]$InputID }

        if ($TargetItem) {
            Write-Host "`nУдаление: $($TargetItem.Name)..." -ForegroundColor Red

            try {
                if ($TargetItem.Type -like "Реестр*") {
                    # Удаляем параметр из реестра
                    Remove-ItemProperty -Path $TargetItem.Path -Name $TargetItem.Name -Force -ErrorAction Stop
                } else {
                    # Удаляем ярлык из папки
                    Remove-Item -Path $TargetItem.Path -Force -ErrorAction Stop
                }
                Write-log "`r`nЭлемент успешно удален из автозагрузки!"
            } catch {
                Write-log "`r`nОшибка: не удалось удалить элемент. Возможно, нужны права Администратора."
            }
        } else {
            Write-log "`r`nЭлемент с таким ID не найден."
        }
    } else {
        Write-log "`r`nНеверный номер, попробуйте еще раз."
    }

})

$Form.Controls.Add($BtnRemoveStartup)

# --- Кнопка 15: Очистка кэша оперативной памяти ---
$BtnReleaseRAM = New-Object System.Windows.Forms.Button
$BtnReleaseRAM.Text = "Оптимизировать ОЗУ"
$BtnReleaseRAM.Font = $FontButton
$BtnReleaseRAM.Location = New-Object System.Drawing.Point(880, 160)
$BtnReleaseRAM.Size = New-Object System.Drawing.Size(160, 40)

$BtnReleaseRAM.Add_Click({
    Write-log "`r`nОптимизация оперативной памяти..."
    $InitialMem = [Math]::Round(((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB))

    # Запускаем сборку мусора .NET памяти текущей сессии
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    $FinalMem = [Math]::Round(((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB))
    $Saved = $FinalMem - $InitialMem
    if ($Saved -gt 0) {
        Write-log "`r`nОптимизация завершена! Освобождено оперативной памяти: $Saved МБ"
    } else {
        Write-log "`r`nПамять уже оптимизирована операционной системой."
    }
})

$Form.Controls.Add($BtnReleaseRAM)

# --- Кнопка 16: Сканирование открытых портов ---
$BtnPortScan = New-Object System.Windows.Forms.Button
$BtnPortScan.Text = "Проверить порт"
$BtnPortScan.Font = $FontButton
$BtnPortScan.Location = New-Object System.Drawing.Point(880, 210)
$BtnPortScan.Size = New-Object System.Drawing.Size(160, 40)

$BtnPortScan.Add_Click({
    $Server = [Microsoft.VisualBasic.Interaction]::InputBox("Введите адрес сервера (например: cbrportal.cbr.ru или 192.168.1.1):", "Проверка порта", "cbrportal.cbr.ru")
    if ([string]::IsNullOrWhiteSpace($Server)) { return }
            
    $PortInput = [Microsoft.VisualBasic.Interaction]::InputBox("Введите номер порта (например: веб-порт 80/443 или порт удаленного рабочего стола 3389):", "Проверка порта", "443")
    if ([string]::IsNullOrWhiteSpace($PortInput)) { return }
    
    $Server = $Server.Trim()
    $PortInput = $PortInput.Trim()
    
    $Port = 0
    if (-not [int]::TryParse($PortInput, [ref]$Port)) {
        Write-log "`r`nОШИБКА: Номер порта должен быть целым числом!"
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        Write-log "`r`nСканирование хоста $Server на порт $Port..."

        # Создаем сетевой клиент .NET
        $TcpClient = New-Object System.Net.Sockets.TcpClient

        # Задаем жесткий тайм-аут на подключение: 2000 миллисекунд (2 секунды)
        $ConnectionTimeout = 2000

        # Запускаем асинхронное подключение, чтобы иметь возможность прервать его по тайм-ауту
        $Ar = $TcpClient.BeginConnect($Server, $Port, $null, $null)
        $Wh = $Ar.AsyncWaitHandle

        # Ждем ровно 2 секунды ответа от сервера
        if (-not $Wh.WaitOne($ConnectionTimeout, $false)) {
            # Если время вышло - сервер не ответил
            $TcpClient.Close()
            Write-log "`r`nВНИМАНИЕ: Порт $Port на сервере $Server ЗАКРЫТ или заблокирован брандмауэром!"
        } else {
            try {
                # Если ответ получен, завершаем подключение для проверки ошибок
                $TcpClient.EndConnect($Ar)
                Write-log "`r`nУСПЕХ: Порт $Port на сервере $Server ОТКРЫТ и отвечает!"
            } catch {
                # Если сервер ответил отказом (Reset)
                Write-log "`r`nВНИМАНИЕ: Порт $Port на сервере $Server ЗАКРЫТ (подключение сброшено)!"
            } finally { $TcpClient.Close() }
        }
        $Wh.Close()
    }
    
})

$Form.Controls.Add($BtnPortScan)

# --- Кнопка 17: Анализ папок с наибольшим объемом ---
$BtnTopFolders = New-Object System.Windows.Forms.Button
$BtnTopFolders.Text = " Топ папок по размеру"
$BtnTopFolders.Font = $FontButton
$BtnTopFolders.Location = New-Object System.Drawing.Point(880, 260)
$BtnTopFolders.Size = New-Object System.Drawing.Size(160, 40)

$BtnTopFolders.Add_Click({
    $userPath = Get-TargetFolder -Description "Выберите ПАПКУ, которую нужно проанализировать:"
    Write-log "`r`nАнализ папок текущего пользователя по пути $userPath (это может занять полминуты)..."

    if (Test-Path $userPath) {
        $report = Get-ChildItem -Path $userPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $size = (Get-ChildItem -Path $_.FullName -File -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            [PSCustomObject]@{ Name = $_.Name; SizeGB = [Math]::Round($size / 1GB, 2) }
            } | Sort-Object SizeGB -Descending | Select-Object -First 5
    
        foreach ($f in $report) {
            Write-log "`r`nПапка в профиле пользователя: $($f.Name) -> Занимает: $($f.SizeGB) ГБ"
        }
    } else {
        Write-log "`r`nПрофиль пользователя: $($f.Name) не найден или заблокирован"
    }    
})

$Form.Controls.Add($BtnTopFolders)

# --- Кнопка 18: Контроль активных сетевых сессий---
$BtnSessions = New-Object System.Windows.Forms.Button
$BtnSessions.Text = "Сетевые сессии"
$BtnSessions.Font = $FontButton
$BtnSessions.Location = New-Object System.Drawing.Point(880, 310)
$BtnSessions.Size = New-Object System.Drawing.Size(160, 40)

$BtnSessions.Add_Click({
    Write-log "`r`nПроверка активных сетевых подключений к ПК..."
    try {
        $sessions = Get-CimInstance Win32_ServerSession -ErrorAction Stop
        if ($sessions) {
            foreach ($s in $sessions) {
                Write-log "`r`nПользователь: $($s.UserName) | Компьютер: $($s.ComputerName) | Открыто файлов: $($s.NumFiles)"
            }
        } else {
            Write-log "`r`nВнешних сетевых подключений к вашему ПК сейчас нет."
        }
    } catch {
        Write-log "`r`nОШИБКА: Для просмотра сессий нужны права Администратора."
    }
})

$Form.Controls.Add($BtnSessions)

# --- Кнопка 19: Мониторинг стабильности системы ---
$BtnReliability = New-Object System.Windows.Forms.Button
$BtnReliability.Text = "Монитор стабильности"
$BtnReliability.Font = $FontButton
$BtnReliability.Location = New-Object System.Drawing.Point(880, 360)
$BtnReliability.Size = New-Object System.Drawing.Size(160, 40)

$BtnReliability.Add_Click({
    Write-log "`r`nЗапуск Монитора стабильности Windows..."
    Start-Process "perfmon.exe" -ArgumentList "/rel"
})

$Form.Controls.Add($BtnReliability)

# --- Кнопка 20: Монитор ресурсов ---
$BtnResMon = New-Object System.Windows.Forms.Button
$BtnResMon.Text = "Монитор ресурсов"
$BtnResMon.Font = $FontButton
$BtnResMon.Location = New-Object System.Drawing.Point(880, 410)
$BtnResMon.Size = New-Object System.Drawing.Size(160, 40)

$BtnResMon.Add_Click({
    Write-log "`r`nЗапуск Монитора ресурсов системы..."
    Start-Process "resmon.exe"
})

$Form.Controls.Add($BtnResMon)

# --- Кнопка 21: Панель общего доступа ---
$BtnShares = New-Object System.Windows.Forms.Button
$BtnShares.Text = "Общие папки ПК"
$BtnShares.Font = $FontButton
$BtnShares.Location = New-Object System.Drawing.Point(880, 460)
$BtnShares.Size = New-Object System.Drawing.Size(160, 40)

$BtnShares.Add_Click({
    Write-log "`r`nОткрытие оснастки общих папок (fsmgmt.msc)..."
    Start-Process "mmc.exe" -ArgumentList "fsmgmt.msc"
})

$Form.Controls.Add($BtnShares)

# --- Кнопка 22: Таймер выключения ---
$BtnSleepTimer = New-Object System.Windows.Forms.Button
$BtnSleepTimer.Text = "Таймер выключения"
$BtnSleepTimer.Font = $FontButton
$BtnSleepTimer.Location = New-Object System.Drawing.Point(880, 510)
$BtnSleepTimer.Size = New-Object System.Drawing.Size(160, 40)

$BtnSleepTimer.Add_Click({
    $timeInput = [Microsoft.VisualBasic.Interaction]::InputBox("Через сколько МИНУТ выключить ПК?`n(Введите '0' для отмены таймера)", "Таймер выключения", "60")
    if ($timeInput -eq $null) { return }
    
    $minutes = 0    
    if ([int]::TryParse($timeInput, [ref]$minutes)) {
        if ($minutes -gt 0) {
            $seconds = $minutes * 60
            shutdown /s /t $seconds
            Write-log "`r`nТаймер установлен! Компьютер выключится через $minutes мин."
        } elseif ($minutes -eq 0) {
            shutdown /a 2>$null
            Write-log "`r`nВсе активные таймеры выключения успешно ОТМЕНЕНЫ."
        } 
    } else {
        Write-log "`r`nОШИБКА: Нужно ввести целое число минут!"
    }
    
})

$Form.Controls.Add($BtnSleepTimer)

# --- Кнопка 23: Выход ---
$BtnExit = New-Object System.Windows.Forms.Button
$BtnExit.Text = " Выход"
$BtnExit.Font = $FontButton
$BtnExit.Location = New-Object System.Drawing.Point(900, 560)
$BtnExit.Size = New-Object System.Drawing.Size(160, 40)

$BtnExit.Add_Click({
    $Form.Close()
})

$Form.Controls.Add($BtnExit)


# --- Запуск окна ---
$Form.TopMost = $true
$Form.Add_Shown({
    $Form.TopMost = $false # как только окно показалось, отпускаем фокус, чтобы оно не мешало другим программам
    $Form.Activate() # делаем окно активным для ввода
    $Form.Focus()
    [void]$SetForegroundWindow::SetForegroundWindow($Form.Handle)
})

$Form.ShowDialog() | Out-Null
$Form.Dispose()