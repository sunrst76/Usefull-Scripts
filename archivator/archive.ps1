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

# Функция для выбора файлов (поддерживает множественный выбор)
function Get-MultipleFiles {
    param($Description)
    Set-WindowToForeground
    
    $Dialog = New-Object System.Windows.Forms.OpenFileDialog
    $Dialog.Title = $Description
    $Dialog.Multiselect = $true
    $Dialog.Filter = "Все файлы (*.*)|*.*"
    
    $MainWindow = New-Object System.Windows.Forms.NativeWindow
    $MainWindow.AssignHandle([System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle)
    
    if ($Dialog.ShowDialog($MainWindow).ToString() -eq "OK") {
        return ,$Dialog.FileNames
    }
    return $null
}

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

# Функция "Универсальное окно" (Умеет возвращать как файлы, так и папки)
function Get-UniversalSelection {
    param($Description)
    Set-WindowToForeground
    
    $Dialog = New-Object System.Windows.Forms.OpenFileDialog
    $Dialog.Title = $Description
    $Dialog.ValidateNames = $false
    $Dialog.CheckFileExists = $false
    $Dialog.CheckPathExists = $true
    $Dialog.Multiselect = $true
    $Dialog.FileName = "Выбрать эту папку или файлы"
    
    $MainWindow = New-Object System.Windows.Forms.NativeWindow
    $MainWindow.AssignHandle([System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle)
    
    if ($Dialog.ShowDialog($MainWindow).ToString() -eq "OK") {
        if ($Dialog.FileName.EndsWith("Выбрать эту папку или файлы")) {
            return ,[System.IO.Path]::GetDirectoryName($Dialog.FileName)
        }
        return ,$Dialog.FileNames
    }
    return $null
}

# Функция выбора существующего ZIP-архива для обновления
function Get-ExistingZipFile {
    param($Description)
    Set-WindowToForeground
    
    $Dialog = New-Object System.Windows.Forms.OpenFileDialog
    $Dialog.Title = $Description
    $Dialog.Filter = "ZIP Архивы (*.zip)|*.zip"
    $Dialog.Multiselect = $false
    
    $MainWindow = New-Object System.Windows.Forms.NativeWindow
    $MainWindow.AssignHandle([System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle)
    
    if ($Dialog.ShowDialog($MainWindow).ToString() -eq "OK") {
        return $Dialog.FileName
    }
    return $null
}

# --- НАЧАЛО ИСПОЛНЕНИЯ СКРИПТА ---

Set-WindowToForeground
Write-Host "=========================================" -ForegroundColor Gray
Write-Host "    БЫСТРАЯ АРХИВАЦИЯ POWERSHELL" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Gray
Write-Host "1. Хочу заархивировать ОДНУ ПАПКУ" -ForegroundColor White
Write-Host "2. Хочу выбрать ФАЙЛЫ (можно из разных папок)" -ForegroundColor White
Write-Host "3. Хочу выбрать НЕСКОЛЬКО ПАПОК (из разных мест)" -ForegroundColor White
Write-Host "4. СУПЕР-РЕЖИМ: Набрать И ПАПКИ, И ФАЙЛЫ вместе" -ForegroundColor Yellow
Write-Host "-----------------------------------------" -ForegroundColor Gray

$Choice = Read-Host "Введите цифру режима (1, 2, 3 или 4) и нажмите Enter"
$SourcePaths = @()
$DefaultName = "Archive"

# Логика сбора данных для режимов 1-4 (осталась прежней)
if ($Choice -eq "1") {
    $SelectedFolder = Get-TargetFolder -Description "Выберите ПАПКУ, которую нужно полностью заархивировать:"
    if (-not $SelectedFolder) { exit }
    $SourcePaths += $SelectedFolder
    $DefaultName = Split-Path $SelectedFolder -Leaf
} elseif ($Choice -eq "2") {
    $Loop = $true
    while ($Loop) {
        $SelectedFiles = Get-MultipleFiles -Description "Зажмите Ctrl или Shift и выберите нужные ФАЙЛЫ:"
        if ($SelectedFiles -and $SelectedFiles.Count -gt 0) {
            $SourcePaths += $SelectedFiles
            Write-Host "Добавлено файлов. Всего в списке: $($SourcePaths.Count)" -ForegroundColor Yellow
            Set-WindowToForeground
            $Response = [System.Windows.Forms.MessageBox]::Show("Хотите перейти в ДРУГУЮ папку и добавить еще файлы?", "Добавление файлов", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($Response.ToString() -eq "No") { $Loop = $false }
        } else { $Loop = $false }
    }
    $DefaultName = "Mixed_Files"
} elseif ($Choice -eq "3") {
    $Loop = $true
    while ($Loop) {
        $SelectedFolder = Get-TargetFolder -Description "Выберите ПАПКУ для добавления в общий архив:"
        if ($SelectedFolder) {
            $SourcePaths += $SelectedFolder
            Write-Host "Добавлена папка. Всего в списке: $($SourcePaths.Count)" -ForegroundColor Yellow
            Set-WindowToForeground
            $Response = [System.Windows.Forms.MessageBox]::Show("Хотите добавить ЕЩЁ ОДНУ папку из другого места?", "Добавление папок", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($Response.ToString() -eq "No") { $Loop = $false }
        } else { $Loop = $false }
    }
    $DefaultName = "Mixed_Folders"
} elseif ($Choice -eq "4") {
    $Loop = $true
    while ($Loop) {
        $Selection = Get-UniversalSelection -Description "Чтобы выбрать файлы — выделите их. Чтобы выбрать текущую папку — ничего не выделяйте и нажмите Открыть."
        if ($Selection) {
            $SourcePaths += $Selection
            Write-Host "Объекты добавлены в очередь. Всего в списке: $($SourcePaths.Count)" -ForegroundColor Yellow
            Set-WindowToForeground
            $Response = [System.Windows.Forms.MessageBox]::Show("Хотите перейти в ДРУГОЕ место и добавить еще папки/файлы?", "Универсальный сборщик", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($Response.ToString() -eq "No") { $Loop = $false }
        } else { $Loop = $false }
    }
    $DefaultName = "Total_Combo_Archive"
} else {
    Write-Host "Неверный ввод. Скрипт завершает работу." -ForegroundColor Red
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
}

if ($SourcePaths.Count -eq 0) {
    Write-Host "Выбор объектов отменен." -ForegroundColor Yellow
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
}

# --- НОВЫЙ БЛОК: ВЫБОР ДЕЙСТВИЯ (НОВЫЙ АРХИВ ИЛИ ОБНОВЛЕНИЕ СТАРОГО) ---
Set-WindowToForeground
Write-Host "`n-----------------------------------------" -ForegroundColor Gray
Write-Host "Что сделать с выбранными объектами?" -ForegroundColor Cyan
Write-Host "1. Создать СОВЕРШЕННО НОВЫЙ архив" -ForegroundColor White
Write-Host "2. ДОБАВИТЬ их в уже существующий архив" -ForegroundColor Yellow
Write-Host "-----------------------------------------" -ForegroundColor Gray
$ActionChoice = Read-Host "Введите цифру действия (1 или 2) и нажмите Enter"

$ZipFullPath = ""
$IsUpdate = $false

if ($ActionChoice -eq "1") {
    # Сценарий создания нового архива (стандартный шаг)
    $DestDir = Get-TargetFolder -Description "Выберите ПАПКУ, куда сохранить готовый ZIP-архив:"
    if (-not $DestDir) {
        Write-Host "Выбор папки сохранения отменен." -ForegroundColor Yellow
        Write-Host "Нажмите любую клавишу для выхода"
        $null = [Console]::ReadKey($true)
        exit
    }
    $DateStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $ZipName = "${DefaultName}_${DateStamp}.zip"
    $ZipFullPath = Join-Path $DestDir $ZipName

 } elseif ($ActionChoice -eq "2") {
    # Сценарий добавления в старый архив
    $ZipFullPath = Get-ExistingZipFile -Description "Выберите СУЩЕСТВУЮЩИЙ ZIP-архив для добавления файлов:"
    if (-not $ZipFullPath) {
        Write-Host "Выбор архива отменен." -ForegroundColor Yellow
        Write-Host "Нажмите любую клавишу для выхода"
        $null = [Console]::ReadKey($true)
        exit
    }
    $IsUpdate = $true
} else {
    Write-Host "Неверный ввод. Скрипт завершает работу." -ForegroundColor Red
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
}

# --- ШАГ ИСПОЛНЕНИЯ АРХИВАЦИИ ---
Set-WindowToForeground
Write-Host "`nОбъектов для обработки: $($SourcePaths.Count)" -ForegroundColor White

if ($IsUpdate) {
    Write-Host "Добавление элементов в существующий архив: $ZipFullPath..." -ForegroundColor Yellow
    try {
        # Используем параметр -Update для добавления файлов без перезаписи старых
        Compress-Archive -Path $SourcePaths -DestinationPath $ZipFullPath -Update
        Write-Host "Успешно! Архив обновлен, новые файлы добавлены." -ForegroundColor Green
    } catch {
        Write-Host "Ошибка при обновлении архива: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Создание нового архива: $ZipFullPath..." -ForegroundColor Cyan
    try {
        Compress-Archive -Path $SourcePaths -DestinationPath $ZipFullPath -Force
        Write-Host "Готово! Новый архив успешно создан." -ForegroundColor Green
    } catch {
        Write-Host "Ошибка при создании архива: $_" -ForegroundColor Red
    }
}

Write-Host "Нажмите любую клавишу для выхода"
$null = [Console]::ReadKey($true)