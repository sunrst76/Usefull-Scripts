Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Speech

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


# ИСПРАВЛЕНО: Новый супер-безопасный класс WinAPI (без структур и маршалинга)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class VolumeHelper {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
}
"@

Write-Host "=== Будильник со смарт-треем ===" -ForegroundColor Cyan

# 1. Запрос параметров
Set-WindowToForeground
$MinutesInput = Read-Host "Через сколько минут подать первый сигнал?"
if (-not ($MinutesInput -match '^\d+$') -or [int]$MinutesInput -le 0) {
    Write-Host "Ошибка: Введите число!" -ForegroundColor Red
    Exit
}

$ReminderText = Read-Host "Введите текст напоминания"
if ([string]::IsNullOrWhiteSpace($ReminderText)) {
    $ReminderText = "Время вышло! Пора переключить задачу."
}

$TotalSeconds = [int]$MinutesInput# * 60
$TargetTime = (Get-Date).AddSeconds($TotalSeconds)

Write-Host "`n[ Таймер запущен ] Сигнал сработает в: $($TargetTime.ToString('HH:mm:ss'))" -ForegroundColor Green
Write-Host "Окно скрывается в трей..." -ForegroundColor Gray
Start-Sleep -Seconds 1

# Находим дескриптор окна
$ConsoleHandle = [VolumeHelper]::GetConsoleWindow()
if ($ConsoleHandle -eq [IntPtr]::Zero -or $ConsoleHandle -eq 0) {
    $ConsoleHandle = (Get-Process -Id $PID).MainWindowHandle
}

# Изначально скрываем окно (Флаг 0 = SW_HIDE)
[void][VolumeHelper]::ShowWindow($ConsoleHandle, 0)

# 2. СОЗДАЕМ ИКОНКУ В СИСТЕМНОМ ТРЕЕ
$TrayIcon = New-Object System.Windows.Forms.NotifyIcon
$TrayIcon.Icon = [System.Drawing.SystemIcons]::Information
$TrayIcon.Visible = $true

# Глобальная переменная для отслеживания состояния
$Global:IsWindowVisible = $false

# Восстановление по ЛЕВОМУ клику мыши
$TrayIcon.Add_Click({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($Global:IsWindowVisible) {
            [void][VolumeHelper]::ShowWindow($ConsoleHandle, 0)
            $Global:IsWindowVisible = $false
        } else {
        [void][VolumeHelper]::ShowWindow($ConsoleHandle, 9) # Восстанавливаем (SW_RESTORE = 9)
        Set-WindowToForeground
        $Global:IsWindowVisible = $true
        }
    }
})

# Контекстное меню (ПРАВЫЙ клик)
$ContextMenu = New-Object System.Windows.Forms.ContextMenu
$ExitMenuItem = New-Object System.Windows.Forms.MenuItem("Выйти из таймера")

$Global:AbortTimer = $false
$ExitMenuItem.Add_Click({
    $Global:AbortTimer = $true
})
$ContextMenu.MenuItems.Add($ExitMenuItem) | Out-Null
$TrayIcon.ContextMenu = $ContextMenu

# 3. Основной цикл таймера
$NeedToRepeat = $true

while ($NeedToRepeat) {
    $Global:AbortTimer = $false
    if ($Global:UserAction -eq "Snooze") {
        Write-Host "`n[ Перенос ] Запуск нового отсчета на $Global:CustomSnoozeMinutes мин..." -ForegroundColor Blue
    }
    
    while ($TotalSeconds -gt 0) {
        if ($Global:AbortTimer) { break }

        # --- ИСПРАВЛЕНО: СУПЕР-БЕЗОПАСНЫЙ СМАРТ-ТРЕЙ БЕЗ СТРУКТУР ---
        if ([VolumeHelper]::IsIconic($ConsoleHandle)) {
            [void][VolumeHelper]::ShowWindow($ConsoleHandle, 0) # Мгновенно скрываем окно в трей
        }
        # -----------------------------------------------------------

        $Min = [Math]::Floor($TotalSeconds / 60)
        $Sec = $TotalSeconds % 60
        $TimeStr = "{0:D2}:{1:D2}" -f [int]$Min, [int]$Sec
        
        $TrayIcon.Text = "Осталось времени: $TimeStr`nНапоминание: $ReminderText"
              
        Write-Host "`rОсталось времени: $TimeStr       " -NoNewline -ForegroundColor Yellow

        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 1
        $TotalSeconds--
    }

    if ($Global:AbortTimer) { break }

    # Звуковое оповещение в фоне
    try {
        $Synthesizer = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $Synthesizer.SpeakAsync("Напоминание. Хозяин, обратите внимание: $ReminderText") | Out-Null
    } catch {}

    # 4. Графическое окно напоминания
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Напоминание"
    $Form.Size = New-Object System.Drawing.Size(420, 220)
    $Form.StartPosition = "Manual"
    $Form.FormBorderStyle = "None" 
    $Form.TopMost = $true
    $Form.BackColor = [System.Drawing.Color]::White

    $Screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $Form.Left = $Screen.Width - $Form.Width - 15
    $Form.Top = $Screen.Height - $Form.Height - 15

    # Синяя панель-шапка
    $HeaderPanel = New-Object System.Windows.Forms.Panel
    $HeaderPanel.Size = New-Object System.Drawing.Size(420, 35)
    $HeaderPanel.Location = New-Object System.Drawing.Point(0, 0)
    $HeaderPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $Form.Controls.Add($HeaderPanel)

    $TitleLabel = New-Object System.Windows.Forms.Label
    $TitleLabel.Location = New-Object System.Drawing.Point(15, 8)
    $TitleLabel.Size = New-Object System.Drawing.Size(300, 20)
    $TitleLabel.ForeColor = [System.Drawing.Color]::White
    $TitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $TitleLabel.Text = "УВЕДОМЛЕНИЕ О ЗАДАЧЕ"
    $HeaderPanel.Controls.Add($TitleLabel)

    $MessageLabel = New-Object System.Windows.Forms.Label
    $MessageLabel.Location = New-Object System.Drawing.Point(20, 55)
    $MessageLabel.Size = New-Object System.Drawing.Size(380, 50)
    $MessageLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $MessageLabel.ForeColor = [System.Drawing.Color]::FromArgb(44, 62, 80)
    $MessageLabel.Text = $ReminderText
    $Form.Controls.Add($MessageLabel)

    $Global:UserAction = "Close"
    $Global:CustomSnoozeMinutes = 5

    $SnoozeInput = New-Object System.Windows.Forms.TextBox
    $SnoozeInput.Location = New-Object System.Drawing.Point(20, 133)
    $SnoozeInput.Size = New-Object System.Drawing.Size(40, 25)
    $SnoozeInput.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $SnoozeInput.Text = "5"
    $Form.Controls.Add($SnoozeInput)

    $MinLabel = New-Object System.Windows.Forms.Label
    $MinLabel.Location = New-Object System.Drawing.Point(65, 135)
    $MinLabel.Size = New-Object System.Drawing.Size(35, 20)
    $MinLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $MinLabel.ForeColor = [System.Drawing.Color]::Gray
    $MinLabel.Text = "мин."
    $Form.Controls.Add($MinLabel)

    # Кнопка "Перенести"
    $SnoozeButton = New-Object System.Windows.Forms.Button
    $SnoozeButton.Location = New-Object System.Drawing.Point(110, 125)
    $SnoozeButton.Size = New-Object System.Drawing.Size(140, 40)
    $SnoozeButton.Text = "Перенести"
    $SnoozeButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $SnoozeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $SnoozeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $SnoozeButton.FlatAppearance.BorderSize = 1
    $SnoozeButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $SnoozeButton.BackColor = [System.Drawing.Color]::White
    $SnoozeButton.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    
    $SnoozeButton.Add_Click({ 
        $Global:UserAction = "Snooze"
        if ($SnoozeInput.Text -match '^\d+$' -and [int]$SnoozeInput.Text -gt 0) {
            $Global:CustomSnoozeMinutes = [int]$SnoozeInput.Text
        }
        $Form.Dispose() 
    })
    $Form.Controls.Add($SnoozeButton)

    # Кнопка "Понятно"
    $CloseButton = New-Object System.Windows.Forms.Button
    $CloseButton.Location = New-Object System.Drawing.Point(280, 125)
    $CloseButton.Size = New-Object System.Drawing.Size(115, 40)
    $CloseButton.Text = "Понятно"
    $CloseButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $CloseButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $CloseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $CloseButton.FlatAppearance.BorderSize = 0
    $CloseButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $CloseButton.ForeColor = [System.Drawing.Color]::White
    
    $CloseButton.Add_Click({ 
        $Global:UserAction = "Close"
        $Form.Dispose() 
    })
    $Form.Controls.Add($CloseButton)

    $Form.Padding = New-Object System.Windows.Forms.Padding(1)
    $Form.Add_Paint({
        param($sender, $e)
        $Pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(218, 218, 218), 1)
        $e.Graphics.DrawRectangle($Pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
    })

    # Переводим окно консоли в скрытый режим перед показом карточки
    [void][VolumeHelper]::ShowWindow($ConsoleHandle, 0)

    # Отображаем форму
    [void]$Form.ShowDialog()

    # Анализ выбора пользователя
    if ($Global:UserAction -eq "Snooze") {
        $TotalSeconds = $Global:CustomSnoozeMinutes# * 60
    } else {
        $NeedToRepeat = $false
    }
}

# 5. Финальный выход: возвращаем окно на экран
$TrayIcon.Visible = $false
$TrayIcon.Dispose()
[void][VolumeHelper]::ShowWindow($ConsoleHandle, 9)

Write-Host "`n=== Работа будильника успешно завершена! ===" -ForegroundColor Cyan
Start-Sleep -Seconds 5
