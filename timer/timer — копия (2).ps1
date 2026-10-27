Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Speech

# Загрузка WinAPI класса
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
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern IntPtr SetActiveWindow(IntPtr hWnd);
}
"@

$DbPath = Join-Path -Path $env:USERPROFILE -ChildPath "powershell_reminders.json"

function Save-Reminders {
    param($Data)
    $Data | ConvertTo-Json -Depth 3 | Out-File -FilePath $DbPath -Encoding utf8 -Force
}

function Load-Reminders {
    if (Test-Path $DbPath) {
        $Content = Get-Content -Path $DbPath -Raw -ErrorAction SilentlyContinue
        if ($Content) { return ConvertFrom-Json -InputObject $Content }
    }
    return $null
}

Write-Host "=== Автономный Планировщик Напоминаний ===" -ForegroundColor Cyan
Write-Host ""

$SavedData = Load-Reminders
$LoadedFromDb = $false

if ($SavedData -and $SavedData.Active -eq $true) {
    Write-Host "[ Обнаружено активное напоминание! ]" -ForegroundColor Cyan
    Write-Host "Текст: $($SavedData.Text)" -ForegroundColor White
    $TargetTime = [DateTime]$SavedData.TargetTime
    $ReminderText = $SavedData.Text
    
    if ($TargetTime -lt (Get-Date)) {
        Write-Host "Время напоминания прошло, пока компьютер был выключен!" -ForegroundColor Red
        $TotalSeconds = 5
    } else {
        $TimeSpan = $TargetTime - (Get-Date)
        $TotalSeconds = [int]$TimeSpan.TotalSeconds
        Write-Host "Напоминание успешно возобновлено." -ForegroundColor Green
    }
    $LoadedFromDb = $true
}

if (-not $LoadedFromDb) {
    Write-Host "Выберите режим напоминания:" -ForegroundColor Yellow
    Write-Host "1. Таймер (через сколько минут)"
    Write-Host "2. Точная дата и время (например, на завтра или конкретный день)"
    $ModeChoice = Read-Host "Введите 1 или 2"

    $TotalSeconds = 0
    $TargetTime = Get-Date

    if ($ModeChoice -eq "2") {
        $DateInput = Read-Host "Введите дату (формат ДД.ММ.ГГГГ, например, 17.09.2026)"
        if (-not ($DateInput -match '^\d{2}\.\d{2}\.\d{4}$')) {
            Write-Host "Ошибка: Неверный формат даты!" -ForegroundColor Red; Exit
        }
        
        $TimeInput = Read-Host "Введите время (формат ЧЧ:ММ, например, 14:30)"
        if (-not ($TimeInput -match '^\d{1,2}:\d{2}$')) {
            Write-Host "Ошибка: Неверный формат времени!" -ForegroundColor Red; Exit
        }
        
        $FullString = "$DateInput $TimeInput"
        try {
            # ИСПРАВЛЕНО: Безопасный парсинг стартовой даты
            $TargetTime = [DateTime]::ParseExact($FullString, "dd.MM.yyyy H:mm", $null)
            $TargetTime = Get-Date $TargetTime -Second 0
        } catch {
            Write-Host "Ошибка: Не удалось распознать дату и время!" -ForegroundColor Red; Exit
        }
        
        if ($TargetTime -lt (Get-Date)) {
            Write-Host "Ошибка: Указанное время уже в прошлом!" -ForegroundColor Red; Exit
        }
        
        $TimeSpan = $TargetTime - (Get-Date)
        $TotalSeconds = [int]$TimeSpan.TotalSeconds
    }
    else {
        $MinutesInput = Read-Host "Через сколько минут管 подать первый сигнал?"
        if ($MinutesInput -match '^\d+$') {
            [int]$MinutesCount = [int]$MinutesInput
            if ($MinutesCount -gt 0) {
                $TotalSeconds = $MinutesCount * 60
                $TargetTime = (Get-Date).AddSeconds($TotalSeconds)
            } else { Write-Host "Ошибка больше нуля!"; Exit }
        } else { Write-Host "Ошибка: Число!"; Exit }
    }

    $ReminderText = Read-Host "Введите текст напоминания"
    if ([string]::IsNullOrWhiteSpace($ReminderText)) {
        $ReminderText = "Время вышло! Пора переключить задачу."
    }

    $Task = @{ TargetTime = $TargetTime.ToString("o"); Text = $ReminderText; Active = $true }
    Save-Reminders -Data $Task
}

# ИСПРАВЛЕНО: Заменен несуществующий цвет Orange на стабильный DarkYellow
Write-Host "`n[ Мониторинг ] Сигнал сработает в: $($TargetTime.ToString('dd.MM.yyyy HH:mm:ss'))" -ForegroundColor Green
Write-Host "Окно скрывается в трей..." -ForegroundColor Gray
Start-Sleep -Seconds 1

$ConsoleHandle = [VolumeHelper]::GetConsoleWindow()
if ($ConsoleHandle -eq [IntPtr]::Zero -or $ConsoleHandle -eq 0) {
    $ConsoleHandle = (Get-Process -Id $PID).MainWindowHandle
}

[void][VolumeHelper]::ShowWindow($ConsoleHandle, 0)
$Global:IsWindowVisible = $false

$TrayIcon = New-Object System.Windows.Forms.NotifyIcon
$TrayIcon.Icon = [System.Drawing.SystemIcons]::Information
$TrayIcon.Visible = $true

$TrayIcon.Add_Click({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($Global:IsWindowVisible) {
            [void][VolumeHelper]::ShowWindow($ConsoleHandle, 0)
            $Global:IsWindowVisible = $false
        } else {
            [void][VolumeHelper]::ShowWindow($ConsoleHandle, 9)
            [void][VolumeHelper]::SetForegroundWindow($ConsoleHandle)
            [void][VolumeHelper]::SetActiveWindow($ConsoleHandle)
            $Global:IsWindowVisible = $true
        }
    }
})

$ContextMenu = New-Object System.Windows.Forms.ContextMenu
$ExitMenuItem = New-Object System.Windows.Forms.MenuItem("Выйти из таймера")
$Global:AbortTimer = $false
$ExitMenuItem.Add_Click({ 
    $Task = @{ TargetTime = $TargetTime.ToString("o"); Text = $ReminderText; Active = $false }
    Save-Reminders -Data $Task
    $Global:AbortTimer = $true 
})
$ContextMenu.MenuItems.Add($ExitMenuItem) | Out-Null
$TrayIcon.ContextMenu = $ContextMenu

$NeedToRepeat = $true
while ($NeedToRepeat) {
    $Global:AbortTimer = $false

    while ($TotalSeconds -gt 0) {
        if ($Global:AbortTimer) { break }

        if ([VolumeHelper]::IsIconic($ConsoleHandle)) {
            [void][VolumeHelper]::ShowWindow($ConsoleHandle, 0)
            $Global:IsWindowVisible = $false
        }

        if ($TotalSeconds -gt 3600) {
            $HoursLeft = [Math]::Floor($TotalSeconds / 3600)
            $MinLeft = [Math]::Floor(($TotalSeconds % 3600) / 60)
            $TimeStr = "$HoursLeft ч. $MinLeft м."
        } else {
            $Min = [Math]::Floor($TotalSeconds / 60)
            $Sec = $TotalSeconds % 60
            $TimeStr = "{0:D2}:{1:D2}" -f [int]$Min, [int]$Sec
        }
        
        $SafeReminder = $ReminderText
        if ($SafeReminder.Length -gt 25) { $SafeReminder = $SafeReminder.Substring(0, 22) + "..." }
        $TrayIcon.Text = "Осталось: $TimeStr | $SafeReminder"
        
        Write-Host "`rОсталось: $TimeStr     " -NoNewline -ForegroundColor Yellow

        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 1
        $TotalSeconds--
    }

    if ($Global:AbortTimer) { break }

    try {
        $Synthesizer = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $Synthesizer.SpeakAsync("Напоминание. Хозяин, обратите внимание: $ReminderText") | Out-Null
    } catch {}

    # 4. Графическое окно карточки (Увеличена высота под календарь)
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Напоминание"
    $Form.Size = New-Object System.Drawing.Size(420, 260)
    $Form.StartPosition = "Manual"
    $Form.FormBorderStyle = "None" 
    $Form.TopMost = $true
    $Form.BackColor = [System.Drawing.Color]::White

    $Screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $Form.Left = $Screen.Width - $Form.Width - 15
    $Form.Top = $Screen.Height - $Form.Height - 15

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

    $CloseIcon = New-Object System.Windows.Forms.Label
    $CloseIcon.Location = New-Object System.Drawing.Point(385, 8)
    $CloseIcon.Size = New-Object System.Drawing.Size(20, 20)
    $CloseIcon.ForeColor = [System.Drawing.Color]::White
    $CloseIcon.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $CloseIcon.Text = "X"
    $CloseIcon.Cursor = [System.Windows.Forms.Cursors]::Hand
    $CloseIcon.Add_Click({ $Global:UserAction = "Close"; $Form.Close() })
    $HeaderPanel.Controls.Add($CloseIcon)

    $MessageLabel = New-Object System.Windows.Forms.Label
    $MessageLabel.Location = New-Object System.Drawing.Point(20, 55)
    $MessageLabel.Size = New-Object System.Drawing.Size(380, 50)
    $MessageLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $MessageLabel.ForeColor = [System.Drawing.Color]::FromArgb(44, 62, 80)
    $MessageLabel.Text = $ReminderText
    $Form.Controls.Add($MessageLabel)

    $Global:UserAction = "Close"

    # Радиокнопка Минуты
    $RadioMin = New-Object System.Windows.Forms.RadioButton
    $RadioMin.Location = New-Object System.Drawing.Point(25, 115)
    $RadioMin.Size = New-Object System.Drawing.Size(120, 25)
    $RadioMin.Text = "Перенести на:"
    $RadioMin.Checked = $true
    $RadioMin.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $Form.Controls.Add($RadioMin)
    
    $SnoozeInput = New-Object System.Windows.Forms.TextBox
    $SnoozeInput.Location = New-Object System.Drawing.Point(150, 115)
    $SnoozeInput.Size = New-Object System.Drawing.Size(45, 25)
    $SnoozeInput.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $SnoozeInput.Text = "5"
    $Form.Controls.Add($SnoozeInput)
    
    $MinLabel = New-Object System.Windows.Forms.Label
    $MinLabel.Location = New-Object System.Drawing.Point(200, 117)
    $MinLabel.Size = New-Object System.Drawing.Size(40, 20)
    $MinLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $MinLabel.ForeColor = [System.Drawing.Color]::Gray
    $MinLabel.Text = "мин."
    $Form.Controls.Add($MinLabel)
    
    # Радиокнопка Календарь
    $RadioTime = New-Object System.Windows.Forms.RadioButton
    $RadioTime.Location = New-Object System.Drawing.Point(25, 150)
    $RadioTime.Size = New-Object System.Drawing.Size(120, 25)
    $RadioTime.Text = "Перенести до:"
    $RadioTime.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $Form.Controls.Add($RadioTime)
    
    $SnoozeDatePicker = New-Object System.Windows.Forms.DateTimePicker
    $SnoozeDatePicker.Location = New-Object System.Drawing.Point(150, 150)
    $SnoozeDatePicker.Size = New-Object System.Drawing.Size(130, 25)
    $SnoozeDatePicker.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $SnoozeDatePicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $SnoozeDatePicker.CustomFormat = "dd.MM.yyyy"
    $Form.Controls.Add($SnoozeDatePicker)
    
    $SnoozeTimeInput = New-Object System.Windows.Forms.TextBox
    $SnoozeTimeInput.Location = New-Object System.Drawing.Point(290, 150)
    $SnoozeTimeInput.Size = New-Object System.Drawing.Size(55, 25)
    $SnoozeTimeInput.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $SnoozeTimeInput.Text = (Get-Date).AddMinutes(10).ToString("HH:mm")
    $Form.Controls.Add($SnoozeTimeInput)
    
    # Кнопка Перенести
    $SnoozeButton = New-Object System.Windows.Forms.Button
    $SnoozeButton.Location = New-Object System.Drawing.Point(110, 195)
    $SnoozeButton.Size = New-Object System.Drawing.Size(140, 40)
    $SnoozeButton.Text = "Перенести"
    $SnoozeButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $SnoozeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $SnoozeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $SnoozeButton.FlatAppearance.BorderSize = 1
    $SnoozeButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $SnoozeButton.BackColor = [System.Drawing.Color]::White
    $SnoozeButton.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $SnoozeButton.Add_Click({ $Global:UserAction = "Snooze"; $Form.Close() })
    $Form.Controls.Add($SnoozeButton)
    
    # Кнопка Понятно
    $CloseButton = New-Object System.Windows.Forms.Button
    $CloseButton.Location = New-Object System.Drawing.Point(280, 195)
    $CloseButton.Size = New-Object System.Drawing.Size(115, 40)
    $CloseButton.Text = "Понятно"
    $CloseButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $CloseButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $CloseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $CloseButton.FlatAppearance.BorderSize = 0
    $CloseButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $CloseButton.ForeColor = [System.Drawing.Color]::White
    $CloseButton.Add_Click({ $Global:UserAction = "Close"; $Form.Close() })
    $Form.Controls.Add($CloseButton)
    
    $Form.Padding = New-Object System.Windows.Forms.Padding(1)
    $Form.Add_Paint({
        param($sender, $e)
        $Pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(218, 218, 218), 1)
        $e.Graphics.DrawRectangle($Pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
    })
    [void][VolumeHelper]::ShowWindow($ConsoleHandle, 0)
    $Global:IsWindowVisible = $false
    [void]$Form.ShowDialog()
    
    # 5. Обработка решения ПОСЛЕ закрытия формы
    if ($Global:UserAction -eq "Snooze") {
        if ($RadioTime.Checked) {
            $SelectedDate = $SnoozeDatePicker.Value.ToString("dd.MM.yyyy")
            $CleanTimeText = ("" + $SnoozeTimeInput.Text).Trim()
    
            # ИСПРАВЛЕНО: Безопасный разбор по регулярному выражению
            if ($CleanTimeText -match '^(\d{1,2}):(\d{2})$') {
                $TimeParts = $CleanTimeText.Split(':')
                $Hours = [int]$TimeParts[0]
                $Minutes = [int]$TimeParts[1]
                
                $BaseDate = [DateTime]::ParseExact($SelectedDate, "dd.MM.yyyy", $null)
                
                $TargetTime = Get-Date $BaseDate -Hour $Hours -Minute $Minutes -Second 0
                
                $TimeSpan = $TargetTime - (Get-Date)
                $TotalSeconds = [int]$TimeSpan.TotalSeconds
                if ($TotalSeconds -le 5) { $TotalSeconds = 60; $TargetTime = (Get-Date).AddSeconds($TotalSeconds) }
            } else {
                $TotalSeconds = 5 * 60; $TargetTime = (Get-Date).AddSeconds($TotalSeconds)
            }
        } else {
            $MinutesValue = if ($SnoozeInput.Text -match '^\d+$' -and [int]$SnoozeInput.Text -gt 0) { [int]$SnoozeInput.Text } else { 5 }
            $TotalSeconds = $MinutesValue * 60
            $TargetTime = (Get-Date).AddSeconds($TotalSeconds)
        }
        $Task = @{ TargetTime = $TargetTime.ToString("o"); Text = $ReminderText; Active = $true }
        Save-Reminders -Data $Task
    
        # ИСПРАВЛЕНО: Цвет заменен на DarkYellow
        Write-Host "`n[ Перенос ] Новое время: $($TargetTime.ToString('dd.MM.yyyy HH:mm:ss'))" -ForegroundColor DarkYellow
    } else {
        $Task = @{ TargetTime = $TargetTime.ToString("o"); Text = $ReminderText; Active = $false }
        Save-Reminders -Data $Task
        $NeedToRepeat = $false
    }
    $Form.Dispose()
}
$TrayIcon.Visible = $false
$TrayIcon.Dispose()
[void][VolumeHelper]::ShowWindow($ConsoleHandle, 9)
Write-Host "`n=== Работа будильника успешно завершена! ===" -ForegroundColor Cyan
