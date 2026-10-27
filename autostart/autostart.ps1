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

Set-WindowToForeground

Write-Host "=== Анализ автозагрузки Windows ===" -ForegroundColor Cyan
Write-Host "Сканирование реестра и системных папок..." -ForegroundColor Gray
Write-Host ""
# 1. Список путей в реестре, где прячется автозагрузка
$RegPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run"
)

$StartupItems = @()
$ID = 1

# Собираем элементы из реестра
foreach ($Path in $RegPaths) {
    if (Test-Path $Path) {
        $Properties = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
        foreach ($Prop in $Properties.PSObject.Properties) {
            # Исключаем системные свойства PowerShell
            if ($Prop.Name -notmatch "PSPath|PSParentPath|PSChildName|PSDrive|PSProvider") {
                $StartupItems += [PSCustomObject]@{
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
        $StartupItems += [PSCustomObject]@{
            ID = $ID
            Name = $File.Name
            Value = $File.FullName
            Type = "Папка Автозагрузка"
            Path = $File.FullName
        }
        $ID++
    }
}

# 2. Вывод красивой таблицы на экран
if ($StartupItems.Count -eq 0) {
    Write-Host "Автозагрузка пуста! Никаких лишних программ не найдено." -ForegroundColor Green
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
}

# Форматируем вывод списком 
foreach ($Item in $StartupItems) {
    Write-Host "[$($Item.ID)] Название: " -NoNewline -ForegroundColor Yellow
    Write-Host $Item.Name -ForegroundColor White -Bold
    Write-Host "   Тип:      $($Item.Type)"
    Write-Host "   Команда:  $($Item.Value)"
    Write-Host "--------------------------------------------------"
}

# 3. Интерактивное меню удаления 
Write-Host ""
Write-Host "Вы можете удалить любой элемент из автозагрузки." -ForegroundColor Cyan
Write-Host "Чтобы выйти, просто нажмите Enter." -ForegroundColor Gray
$UserChoice = Read-Host "Введите [ID] элемента для УДАЛЕНИЯ"

if ($UserChoice -match '^\d+$') {
    $TargetItem = $StartupItems | Where-Object { $_.ID -eq [int]$UserChoice }

    if ($TargetItem) {
        Write-Host "`nУжадение: $($TargetItem.Name)..." -ForegroundColor Red

        try {
            if ($TargetItem.Type -like "Реестр*") {
                # Удаляем параметр из реестра
                Remove-ItemProperty -Path $TargetItem.Path -Name $TargetItem.Name -Force -ErrorAction Stop
            } else {
                # Удаляем ярлык из папки
                Remove-Item -Path $TargetItem.Path -Force -ErrorAction Stop
            }
            Write-Host "Элемент успешно удален из автозагрузки!" -ForegroundColor Green
        } catch {
            Write-Host "Ошибка: не удалось удалить элемент. Возможно, нужны права Администратора." -ForegroundColor Red
        }
    } else {
        Write-Host "Элемент с таким ID не найден." -ForegroundColor Orange
    }
} else {
    Write-Host "Выход без изменений." -ForegroundColor Gray
}

Write-Host "Нажмите любую клавишу для выхода"
$null = [Console]::ReadKey($true)
exit