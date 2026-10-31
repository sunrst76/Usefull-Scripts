Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

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

function Get-PasswordDialog {
    param ([string]$Title = "Запрос пароля")
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(350, 160) # Немного увеличили высоту для чекбокса
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true 

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Введите секретный пароль для доступа к файлу:"
    $label.Location = New-Object System.Drawing.Point(20, 15)
    $label.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(20, 40)
    $textBox.Size = New-Object System.Drawing.Size(290, 20)
    $textBox.PasswordChar = '*' 
    $form.Controls.Add($textBox)

    # Добавляем флажок "Показать пароль"
    $checkbox = New-Object System.Windows.Forms.CheckBox
    $checkbox.Text = "Показать пароль"
    $checkbox.Location = New-Object System.Drawing.Point(20, 65)
    $checkbox.Size = New-Object System.Drawing.Size(150, 20)
    
    # Логика переключения: если галочка стоит, убираем маску (ставим [char]0), иначе возвращаем '*'
    $checkbox.Add_CheckedChanged({
        if ($checkbox.Checked) {
            $textBox.PasswordChar = [char]0
        } else {
            $textBox.PasswordChar = '*'
        }
    })
    $form.Controls.Add($checkbox)

    $buttonOK = New-Object System.Windows.Forms.Button
    $buttonOK.Text = "OK"
    $buttonOK.Location = New-Object System.Drawing.Point(125, 95) # Сместили кнопку чуть ниже
    $buttonOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $buttonOK
    $form.Controls.Add($buttonOK)

    $form.Add_Shown({ $form.Activate(); $textBox.Focus() })

    $result = $form.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $textBox.Text
    }
    return $null
}


Set-WindowToForeground

Write-Host "=== ПРОФЕССИОНАЛЬНЫЙ 'СЕКРЕТНЫЙ СЕЙФ' ЗАПУЩЕН ===" -ForegroundColor Green

# --- ШАГ 1: Выбор файла через стандартное окно Windows ---
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.Title = "Выберите файл для шифрования или расшифровки"
$openFileDialog.Filter = "Все файлы (*.*)|*.*"

if ($openFileDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "Действие отменено пользователем." -ForegroundColor Yellow
    Write-Host "`nНажмите любую клавишу для завершения работы..."
    $null = [Console]::ReadKey($true)
    Exit
}

$filePath = $openFileDialog.FileName
$fileExtension = [System.IO.Path]::GetExtension($filePath)

# --- ШАГ 2: Запрос пароля у пользователя ---
$password = Get-PasswordDialog -Title "Секретный сейф (Максимальная защита)"

if ([string]::IsNullOrEmpty($password)) {
    Write-Host "Пароль не введен. Выход." -ForegroundColor Red
    Write-Host "`nНажмите любую клавишу для завершения работы..."
    $null = [Console]::ReadKey($true)
    Exit
}

# --- ШАГ 3: Логика КРИПТОГРАФИИ (AES-256 с динамической солью) ---
try {
    $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
    $aes = [System.Security.Cryptography.Aes]::Create()

    if ($fileExtension -ne ".locked") {
        # =========================================================================
        # РЕЖИМ 1: ШИФРОВАНИЕ (Генерация соли и склейка)
        # =========================================================================
        Write-Host "Шифрование файла: $filePath..." -ForegroundColor Yellow
        
        # 1. Генерируем абсолютно уникальную случайную соль (16 байт)
        $salt = New-Object byte[] 16
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($salt)
        $rng.Dispose()

        # 2. Создаем ключ на базе пароля и НАШЕЙ НОВОЙ СЛУЧАЙНОЙ соли
        $deriveBytes = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $salt, 20000) # Увеличили циклы до 20 000
        $aes.Key = $deriveBytes.GetBytes(32) # 256-бит ключ
        $aes.IV = $deriveBytes.GetBytes(16)  # 128-бит вектор
        $deriveBytes.Dispose()

        # 3. Шифруем данные файла
        $encryptor = $aes.CreateEncryptor()
        $encryptedBytes = $encryptor.TransformFinalBlock($fileBytes, 0, $fileBytes.Length)
        $encryptor.Dispose()

        # 4. СКЛЕЙКА: Создаем итоговый массив (16 байт соли + зашифрованные байты)
        $finalContainer = New-Object byte[] ($salt.Length + $encryptedBytes.Length)
        [System.Buffer]::BlockCopy($salt, 0, $finalContainer, 0, $salt.Length)
        [System.Buffer]::BlockCopy($encryptedBytes, 0, $finalContainer, $salt.Length, $encryptedBytes.Length)

        # 5. Записываем контейнер на диск с расширением .locked
        $newFilePath = $filePath + ".locked"
        [System.IO.File]::WriteAllBytes($newFilePath, $finalContainer)
        
        # Безопасное затирание оригинала нулями (Wipe)
        $emptyBytes = New-Object byte[] $fileBytes.Length
        [System.IO.File]::WriteAllBytes($filePath, $emptyBytes)
        Remove-Item -Path $filePath -Force
        
        Write-Host "[УСПЕХ] Файл зашифрован со случайной солью: $newFilePath" -ForegroundColor Green
        [System.Windows.Forms.MessageBox]::Show("Файл успешно защищен динамической солью! Оригинал бесследно удален.", "Секретный сейф")
        
    } else {
        # =========================================================================
        # РЕЖИМ 2: РАСШИФРОВКА (Парсинг соли из заголовка)
        # =========================================================================
        Write-Host "Расшифровка файла: $filePath..." -ForegroundColor Yellow
        
        if ($fileBytes.Length -le 16) {
            throw "Файл поврежден или слишком мал, чтобы содержать крипто-ключи."
        }

        # 1. РАЗДЕЛЕНИЕ: Откусываем первые 16 байт — это наша динамическая соль
        $salt = New-Object byte[] 16
        [System.Buffer]::BlockCopy($fileBytes, 0, $salt, 0, 16)

        # 2. Вырезаем оставшуюся часть файла — это чистые зашифрованные данные
        $encryptedBytesLength = $fileBytes.Length - 16
        $encryptedBytes = New-Object byte[] $encryptedBytesLength
        [System.Buffer]::BlockCopy($fileBytes, 16, $encryptedBytes, 0, $encryptedBytesLength)

        # 3. Передаем вытащенную соль в PBKDF2 для воссоздания оригинального ключа
        $deriveBytes = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $salt, 20000)
        $aes.Key = $deriveBytes.GetBytes(32)
        $aes.IV = $deriveBytes.GetBytes(16)
        $deriveBytes.Dispose()

        # 4. Пытаемся расшифровать
        $decryptor = $aes.CreateDecryptor()
        $decryptedBytes = $decryptor.TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)
        $decryptor.Dispose()

        # 5. Возвращаем оригинальное расширение (стираем .locked)
        $newFilePath = $filePath.Substring(0, $filePath.Length - 7)
        [System.IO.File]::WriteAllBytes($newFilePath, $decryptedBytes)
        
        # Удаляем зашифрованный контейнер
        Remove-Item -Path $filePath -Force
        
        Write-Host "[УСПЕХ] Ключ совпал, соль извлечена. Файл восстановлен: $newFilePath" -ForegroundColor Green
        [System.Windows.Forms.MessageBox]::Show("Сейф успешно открыт! Файл восстановлен в исходный вид.", "Секретный сейф")
    }
}
catch {
    $errMessage = $_.Exception.Message
    Write-Host "[ОШИБКА] Не удалось обработать файл. Техническая инфо: $errMessage" -ForegroundColor Red
    
    if ($errMessage -match "Загрузочный" -or $errMessage -match "Padding" -or $errMessage -match "cryptographic") {
        [System.Windows.Forms.MessageBox]::Show("Неверный пароль! Криптографический ключ не совпал с солью сейфа.", "Ошибка доступа", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } else {
        [System.Windows.Forms.MessageBox]::Show("Ошибка файловой системы!`nВозможно, файл открыт в другой программе или заблокирован.`n`nДетали: $errMessage", "Ошибка файла", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
}


Write-Host "`nНажмите любую клавишу для завершения работы..."
$null = [Console]::ReadKey($true)