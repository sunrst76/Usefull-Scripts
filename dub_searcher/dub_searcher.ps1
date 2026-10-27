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

# Выбор пути поиска дубликатов
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
    $Dialog.InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
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

Set-WindowToForeground

$TargetFolder = Get-UniversalSelection -Description "Чтобы выбрать файлы — выделите их. Чтобы выбрать текущую папку — ничего не выделяйте и нажмите Открыть."

Write-Host " === Запуск поиска дубликатов ===" -ForegroundColor Cyan
Write-Host "Сканирование папки: $TargetFolder" -ForegroundColor Yellow
Write-Host "Это может занять продолжительное время, если файлов много..." -ForegroundColor Gray

if (-not (Test-Path $TargetFolder)) {
    Write-Host "Ошибка: Отмена выбора пути" -ForegroundColor Red
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
}
# 1. Собираем все файлы и считаем их SHA256 хэш
$AllFiles = Get-ChildItem -Path $TargetFolder -File -Recurse -ErrorAction SilentlyContinue

Write-Host "Найдено файлов для анализа: $($AllFiles.Count)" -ForegroundColor Gray
Write-Host "Вычисляю хэш-суммы..." -ForegroundColor Gray

$HashDatabase = @()

foreach ($File in $AllFiles) {
    try {
        # Считаем хэш (SHA256 по умолчанию)
        $FileHash = Get-FileHash -Path $File.FullName -Algorithm SHA256 -ErrorAction Stop

        # Добавляем данные в наш массив
        $HashDatabase += [PSCustomObject]@{
            Name     = $File.Name
            FullName = $File.FullName
            SizeMB   = [Math]::Round($File.Length / 1MB, 2)
            Hash     = $FileHash.Hash
        }
    }
    catch {
        # Пропускаем файлы, к которым нет доступа (заняты системой)
        continue
    }
}

# 2. Группируем файлы по одинаковому хэшу и фильтруем те, у которых есть дубликаты
$Duplicates = $HashDatabase | Group-Object -Property Hash | Where-Object { $_.Count -gt 1 }

if ($Duplicates.Count -eq 0) {
    Write-Host "`n[ Успех ] Дубликаты не найдены! Все файлы уникальны." -ForegroundColor Green
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
}

Write-Host "`n=== Найдены дубликаты ===" -ForegroundColor Red

# Выводим найденные дубликаты на экран 
foreach ($Group in $Duplicates) {
    Write-Host "`nОдинаковые файлы (Хэш: $($Group.Name.Substring(0,10))...):" -ForegroundColor Cyan
    foreach ($File in $Group.Group) {
        Write-Host " -> [$($File.SizeMB) MB] $($File.FullName)" -ForegroundColor White
    }
}

# Интерактивное меню удаления 
Write-Host "`n===============================================" -ForegroundColor Yellow
Write-Host "Что вы хотите сделать с дубликатами?"-ForegroundColor Yellow
Write-Host "1. Ничего (просто закрыть скрипт)"
Write-Host "2. Автоматически УДАЛИТЬ копии (оставить только по ОДНОМУ оригиналу из каждой группы)"
$Choice = Read-Host "Введите номер действия (1 или 2)"

if ($Choice -eq "2") {
    Write-Host "`nУдаление копий..."-ForegroundColor Red
    foreach ($Group in $Duplicates) {
        # Умная сортировка: Файлы со словом "копия", "copy" или "(1)" принудительно двигаем вниз списка
        $SortedGroup = $Group.Group | Sort-Object {
            if ($_.Name -match 'копия|copy|\(\d+\)') { 1 } else { 0 }
        }
        
        # Оставляем первый файл как оригинал, остальные (копии) берем в оборот
        $OriginalFile = $SortedGroup | Select-Object -First 1
        $FilesToDelete = $SortedGroup | Select-Object -Skip 1

        foreach ($File in $FilesToDelete) {
            try {
                Remove-Item -Path $File.FullName -Force -ErrorAction Stop
                Write-Host "Удалено: $($File.FullName)" -ForegroundColor Gray
            } catch {
                Write-Host "Не удалось удалить: $($File.FullName) (Файл занят)" -ForegroundColor DarkRed
            }
        }
    }
    Write-Host "`n=== Очистка дубликатов завершена! ===" -ForegroundColor Green
}
else {
    Write-Host "`nСкрипт завершен без удаления файлов." -ForegroundColor Gray
}
Write-Host "Нажмите любую клавишу для выхода"
$null = [Console]::ReadKey($true)
exit