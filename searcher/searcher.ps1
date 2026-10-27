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
    
# Функция запроса критерия поиска
function Get-Pattern {
    Set-WindowToForeground
    $InputForm = New-Object System.Windows.Forms.Form
    $InputForm.Text = "Параметры поиска"
    $InputForm.Size = New-Object System.Drawing.Size(400,180)
    $InputForm.StartPosition = "CenterScreen"
    $InputForm.FormBorderStyle = "FixedDialog"
    $InputForm.MaximizeBox = $false

    $Label = New-Object System.Windows.Forms.Label
    $Label.Location = New-Object System.Drawing.Point(20,20)
    $Label.Size = New-Object System.Drawing.Size(350,20)
    $Label.Text = "Введите текст или фразу для поиска:"

    $TextBox = New-Object System.Windows.Forms.TextBox
    $TextBox.Location = New-Object System.Drawing.Point(20,50)
    $TextBox.Size = New-Object System.Drawing.Size(340,20)

    $Button = New-Object System.Windows.Forms.Button
    $Button.Location = New-Object System.Drawing.Point(140,90)
    $Button.Size = New-Object System.Drawing.Size(100,30)
    $Button.Text = "Искать"
    $Button.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $InputForm.Controls.Add($Label)
    $InputForm.Controls.Add($TextBox)
    $InputForm.Controls.Add($Button)
    $InputForm.AcceptButton = $Button
    $InputForm.TopMost = $true
    $InputForm.Add_Shown({
        $TextBox.Focus()
        $InputForm.Activate()
    })
	
    if ($InputForm.ShowDialog() -ne "OK" -or [string]::IsNullOrWhiteSpace($TextBox.Text)) {
        Write-Host "Поиск отменен или введен пустой запрос." -ForegroundColor Yellow
        Write-Host "Нажмите любую клавишу для выхода"
        $null = [Console]::ReadKey($true)
        exit
    }
    $SearchText = $TextBox.Text
return $SearchText
}

# Функция получения пути для сохранения результатов поиска файлов без сжатия
function Get-PathSearchResultTxt {
    
    [CmdletBinding()]
    param(
    [string]$Title = "Сохранить результы поиска по файлам txt, xml и др. как...",
    [string]$Filter = "CSV файлы (*.csv)|*.csv|Все файлы (*.*)|*.*",
    [string]$InitialDirectory = [Environment]::GetFolderPath("Desktop"),
    [string]$DefaultFileName = "search_result_txt.csv")
    
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

# Функция получения пути для сохранения результатов поиска файлов со сжатием
function Get-PathSearchResult {
    
    [CmdletBinding()]
    param(
    [string]$Title = "Сохранить результы поиска по остальным файлам как...",
    [string]$Filter = "CSV файлы (*.csv)|*.csv|Все файлы (*.*)|*.*",
    [string]$InitialDirectory = [Environment]::GetFolderPath("Desktop"),
    [string]$DefaultFileName = "search_result.csv")
    
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


$SourcePaths = @()
#$DefaultName = "search_result"

$Selection = Get-UniversalSelection -Description "Чтобы выбрать файлы — выделите их. Чтобы выбрать текущую папку — ничего не выделяйте и нажмите Открыть."

# Проверяем, что папка для поиска выбрана
if ($Selection -ne $null) {

# Проверяем, что критерий поиска задан
$Pattern = Get-Pattern
if ($Pattern -ne $null) {
	Set-WindowToForeground
    
    # 1. Блок поиска по файлам без сжатия
    Write-Host " >>> Выполняю поиск по файлам без сжатия..." 
    $isMatch = Get-ChildItem -Path $Selection -File -Include *.txt, *.log, *.xml, *.ini, *.htm, *.html, *.csv -Recurse | Select-String -Pattern $Pattern
            
    if ($isMatch -ne $null) {
        $CsvPathTxt = Get-PathSearchResultTxt
        if ($CsvPathTxt -eq $null) {
            Set-WindowToForeground
            Write-Host "Файл сохранения результатов поиска не выбран"
            Write-Host "Нажмите любую клавишу для выхода"
            $null = [Console]::ReadKey($true)
            exit
        }
        Set-WindowToForeground
        Get-ChildItem -Path $Selection -File -Include *.txt, *.log, *.xml, *.ini, *.htm, *.html, *.csv -Recurse | Select-String -Pattern $Pattern | Select-Object Path, LineNumber, Line | Export-Csv -Path $CsvPathTxt -Delimiter ";" -Encoding UTF8 -NoTypeInformation
        Write-Host "Результаты поиска по файлам без сжатия и шифрования через командлет Select-String сохранены в: $CsvPathTxt"
                
    } else {
        Write-Host "Ничего не найдено по файлам без сжатия и шифрования через командлет Select-String"                
    }
    
    # 2. Блок поиска по файлам со сжатием                               
    # Подключение .NET класса для работы с zip-архивами
    Add-Type -AssemblyName System.IO.Compression.FileSystem
                
    # Массив для хранения результатов
    $Results = @()
            
                                
    # Получаем файлы 
    $GetFiles = Get-ChildItem -Path $Selection -File -Include *.doc, *.docx, *.xls, *.xlsx, *.zip, *.rar, *.pdf -Recurse -ErrorAction SilentlyContinue
    $totalFiles = $GetFiles.Count
    $currentIndex = 0    
                        
    $GetFiles | ForEach-Object {
                    
        $currentIndex++
        $CurrentFile = $_.FullName
        $extension = $_.Extension.ToLower()
        $Status = "Не найдено"

        $percentComplete = [Math]::Round(($currentIndex / $totalFiles) * 100)
        Write-Progress -Activity "Идет сканирование документов..." `
                        -Status "Обработка файлов $currentIndex из $totalFiles : $($_.Name)" `
                        -PercentComplete $percentComplete
                    
        # Обработка современного формата .docx, .xlsx
        if ($_.Extension -eq ".docx" -or $_.Extension -eq ".xlsx") {
            try {
                # Загружаем типы для работы с zip-архивами
                Add-Type -AssemblyName WindowsBase
                            
                # Открываем docx как пакет в режиме чтения
                $package = [System.IO.Packaging.Package]::Open($CurrentFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)

                # Находим часть пакета, отвечающую за главный документ
                if ($_.Extension -eq ".docx") {
                    $docUri = [System.Uri]::new("/word/document.xml", [System.UriKind]::Relative)
                } else {
                    $docUri = [System.Uri]::new("/xl/sharedStrings.xml", [System.UriKind]::Relative)
                }
                if ($package.PartExists($docUri)) {
                                
                    $part = $package.GetPart($docUri)
                    $stream = $part.GetStream()
                                
                    $xmlDoc = New-Object System.Xml.XmlDocument
                    $xmlDoc.Load($stream)
                                                                                              
                    $stream.Close()
                                
                    # Декодируем XML-сущности (заменяет &amp; на &, &quot; на кавычки и т.д.)
                    $cleanText = $xmlDoc.DocumentElement.InnerText

                    # Проверяем наличие фразы
                    if ($cleanText -match [regex]::Escape($Pattern)) {
                        $Status = "Найдено"
                        Write-Host "Текст найден: $CurrentFile" -ForegroundColor Green
                    }                        
                }
                            
            } catch { $Status = "Ошибка DOCX, XLSX" }
                        
            finally {
                if ($package) { $package.Close() }
            }
        # Обработка старого формата .doc, .xls
        } elseif ($_.Extension -eq ".doc" -or $_.Extension -eq ".xls") {
            try {
                # Читаем файл как набор байт
                $Bytes = [System.IO.File]::ReadAllBytes($CurrentFile)
                
                # Декодируем в строку (в старых Word-файлах текст обычно в Юникоде)
                $RawText = [System.Text.Encoding]::Unicode.GetString($Bytes)
                            
                if ($RawText -match [regex]::Escape($Pattern)) { $Status = "Найдено" }
            } catch { $Status = "Ошибка DOC, XLS" }                                      
                                        
        # Обработка ZIP архивов
        } elseif ($_.Extension -eq ".zip") {
            try {
                Add-Type -AssemblyName System.IO.Compression
                Add-Type -AssemblyName WindowsBase
                Add-Type -AssemblyName System.Web

                $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($CurrentFile)

                # Массив для хранения имен всех найденных внутри файлов
                $foundInside = @()

                foreach ($entry in $zipArchive.Entries) {
                            
                # Извлекаем поток файла в память 
                            
                    if ($entry.Length -eq 0) { continue }
                                
                    # Обрабатываем файлы современных форматов внутри архива
                    if ($entry.Name -match '\.(docx|xlsx)') {
                            $stream = $entry.Open()

                            $memStream = New-Object System.IO.MemoryStream
                            $stream.CopyTo($memStream)
                            $stream.Close()

                            $null = $memStream.Seek(0, [System.IO.SeekOrigin]::Begin)
                                        
                            $package = [System.IO.Packaging.Package]::Open($memStream, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
                                        
                            $innerPath = if ($entry.Name -like "*.docx") { "/word/document.xml" } else { "/xl/sharedStrings.xml" }
                            $docUri = [System.Uri]::new($innerPath, [System.UriKind]::Relative)

                            if ($package.PartExists($docUri)) {
                                $part = $package.GetPart($docUri)
                                $partStream = $part.GetStream()
                                                                                                                                                        
                                $xmlDoc = New-Object System.Xml.XmlDocument
                                $xmlDoc.Load($partStream)
                                $partStream.Close()

                                $cleanText = [System.Net.WebUtility]::HtmlDecode($xmlDoc.DocumentElement.InnerText)

                                    if ($cleanText -match [regex]::Escape($Pattern)) {
                                        
                                        # Добавляем имя файла в массив
                                        $foundInside += $entry.Name   
                                    }
                            }
                            $package.Close()
                            $stream.Close()                                                                     
                    }

                    # Обрабатываем файлы старых форматов внутри архива
                    if ($entry.Name -match '\.(doc|xls)') {
                        $stream = $entry.Open()
                        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::GetEncoding("windows-1251"))
                        $textAnsi = $reader.ReadToEnd()
                        $reader.Close()
                        $stream.Close()

                        if ($textAnsi -match [regex]::Escape($Pattern)) {
                            $foundInside += $entry.Name                                
                        }
                    }
                }
                if ($foundInside.Count -gt 0){
                    $Status = "Найдено в: " + ($foundInside -join ", ")
                }
                                                                    
            } catch { 
                    $Status = "Ошибка zip" 
                    Write-Error $_.Exception.Message
                }
            finally {
                if ($zipArchive) { $zipArchive.Dispose() }
            }
                
        # Обработка rar архивов                          
        } elseif ($_.Extension -eq ".rar") {
            try {
                # Читаем весь RAR-файл в массив байт
                $fileBytes = [System.IO.File]::ReadAllBytes($CurrentFile)
            
                if ($fileBytes -and $fileBytes.Count -gt 0) {
                    # Переводим вашу поисковую фразу в байты трех основных кодировок
                    $patternBytesUTF8  = [System.Text.Encoding]::UTF8.GetBytes($Pattern)
                    $patternBytes1251  = [System.Text.Encoding]::GetEncoding("windows-1251").GetBytes($Pattern)
                    $patternBytesUnic  = [System.Text.Encoding]::Unicode.GetBytes($Pattern)
                    $patternBytesBigE  = [System.Text.Encoding]::BigEndianUnicode.GetBytes($Pattern) 

                    # Внутренняя функция для быстрого поиска совпадения массивов байт
                    $searchBytes = {
                        param([byte[]]$file, [byte[]]$search)
                        if ($search.Count -eq 0 -or $file.Count -lt $search.Count) { return $false }
                        for ($i = 0; $i -le ($file.Count - $search.Count); $i++) {
                            $match = $true
                            for ($j = 0; $j -lt $search.Count; $j++) {
                                if ($file[$i + $j] -ne $search[$j]) { $match = $false; break }
                            }
                            if ($match) { return $true }
                        }
                        return $false
                    }

                    # Запускаем побайтовую проверку по всем трем кодировкам
                    $isFound = (&$searchBytes $fileBytes $patternBytesUTF8) -or 
                               (&$searchBytes $fileBytes $patternBytes1251) -or 
                               (&$searchBytes $fileBytes $patternBytesUnic) -or
                               (&$searchBytes $fileBytes $patternBytesBigE)

                    if ($isFound) {
                        $Status = "Найдено внутри RAR"
                    }
                                
                }
                                                                                                                          
            } catch { 
                    $Status = "Ошибка rar" 
                    Write-Error $_.Exception.Message
            }
        
        # Обработка pdf файлов     
        } elseif ($_.Extension -eq ".pdf") {                                                
            Write-Host ">>> Расшифровываю PDF: $($_.Name)..." -ForegroundColor DarkGray
            try {                            
                if (Test-Path $CurrentFile -PathType Leaf) {
                    # ---ШАГ 1: СВЕРХБЫСТРОЕ ЧТЕНИЕ БАЙТ (0.001 секунды) ---
                    # Читаем напрямую в память без блокировки потоков и ошибок конструкторов
                    $fileBytes = [System.IO.File]::ReadAllBytes($CurrentFile)
                    $rawText = [System.Text.Encoding]::GetEncoding(1251).GetString($fileBytes)

                    # Безопасное регулярное выражение без диапазонов \х
                    $cleanText = [regex]::Replace($rawText, '[^a-zA-Z0-9а-яА-ЯёЁ\s\p{P}]', '')

                    # Если текст найден быстрым способом, сразу ставим статус 
                    if ($cleanText -and ($cleanText -match [regex]::Escape($Pattern))) {
                        $Status = "Найдено внутри PDF"
                    } 
                    else {
                        # --- ШАГ 2: МЕДЛЕННЫЙ WORD (Запускается только если быстрый шаг не нашел текст) ---
                        $wordApp = $null
                        $doc = $null
                        try {
                            wordApp = New-Object -ComObject Word.Application
                            $wordApp.Visible = $false
                            $wordApp.DisplayAlerts = 0

                            $doc = $wordApp.Documents.Open($CurrentFile, $false, $true, $false)
                            $pdfText = $doc.Content.Text

                            $doc.Close($false)
                            $wordApp.Quit()
                                                                       
                            if ($pdfText -match [regex]::Escape($Pattern)) {
                                $Status = "Найдено внутри PDF"
                            } else {
                                $Status = "Не найдено"
                            }
                        }
                        catch {
                            # Если Word упал (например, из-за размера страниц чертежа), 
                            # глушим ошибку и ставим "Не найдено", чтобы скрипт шел дальше
                            $Status = "Не найдено"
                        }
                        finally {
                            # Надежная очистка процессов Word из памяти
                            if ($doc) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) | Out-Null }
                            if ($wordApp) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wordApp) | Out-Null }
                            [System.GC]::Collect()
                            [System.GC]::WaitForPendingFinalizers()
                        }
                    }
                                                             
                } else {
                    Write-Host "Файл не найден по пути: $Selection" -ForegroundColor Red
                    $Status = "Ошибка: файл не найден"
                }
                                                                                                                          
            } catch { 
                    $Status = "Ошибка pdf" 
                    Write-Error $_.Exception.Message
                    if ($reader) { $reader.Close() }
                    if ($fileStream) { $fileStream.Close() }
            }
        }                
        
        # Вывод прогресса в консоль
        if ($Status -like "Найдено*") {                        
            Write-Host "$Status : $($_.Name)" -ForegroundColor Green
            $Results += [PSCustomObject]@{ Файл = $_.Name; Путь = $CurrentFile; Статус = $Status }
        } elseif ($Status -like "Ошибка*") {
            Write-Host "Ошибка при обработке: $($_.Name)" -ForegroundColor Red
        } <#else {
            Write-Host "Проверен: $($_.Name) (Не найдено)" -ForegroundColor Gray
        }#>
                    
        Write-Progress -Activity "Идет сканирование документов..." -Completed  
        } 
}
# Проверяем, есть ли хоть один найденный файл в массиве результатов
if ($Results.Count -gt 0) {
    $сsvPath = Get-PathSearchResult
    if ($сsvPath -eq $null) {
            Set-WindowToForeground
            Write-Host "Файл сохранения результатов поиска не выбран"
            Write-Host "Нажмите любую клавишу для выхода"
            $null = [Console]::ReadKey($true)
            exit
    }
    # Экспорт результатов в CSV (с поддержкой кириллицы)
    $Results | Export-Csv -Path $сsvPath -Delimiter ';' -NoTypeInformation -Encoding UTF8
    Set-WindowToForeground
    Write-Host "Поиск завершен. Результаты сохранены в: $сsvPath" -ForegroundColor Cyan
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
                    
} else {
    # Сюда попадает только если массив результатов действительно пуст
    Set-WindowToForeground
    Write-Host "Ничего не найдено по файлам со сжатием"
    Write-Host "Нажмите любую клавишу для выхода"
    $null = [Console]::ReadKey($true)
    exit
}

} else {
	Write-Host "Выбор папки или файла(ов) для поиска отменен" -ForegroundColor Green
	Write-Host "Нажмите любую клавишу для выхода"
    	$null = [Console]::ReadKey($true)
    	exit
}