Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# WinAPI класс для скрытия/показа окон
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

# ЖЕСТКАЯ ЗАЩИТА ОТ ДУБЛИКАТОВ: Убиваем старые фоновые процессы этого скрипта
$CurrentPID = $PID
$AllProcesses = Get-Process -Name "powershell" -ErrorAction SilentlyContinue
foreach ($P in $AllProcesses) {
    if ($P.Id -ne $CurrentPID) {
        $WinTitle = (Get-Process -Id $P.Id).MainWindowTitle
        if ($WinTitle -match "Менеджер Напоминаний" -or $WinTitle -match "timer") {
            Stop-Process -Id $P.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

$DbPath = Join-Path -Path $env:USERPROFILE -ChildPath "powershell_reminders.json"

# Автоматическое исправление базы данных от NULL-ошибок прошлых запусков
if (Test-Path $DbPath) {
    $ContentRaw = Get-Content -Path $DbPath -Raw -ErrorAction SilentlyContinue
    if ($ContentRaw) {
        $CheckDb = ConvertFrom-Json -InputObject $ContentRaw -ErrorAction SilentlyContinue
        $HasBadItems = $false
        if ($CheckDb) {
            foreach ($Item in @($CheckDb)) {
                if ($null -eq $Item.Id -or $null -eq $Item.TargetTime) { $HasBadItems = $true }
            }
        }
        if ($HasBadItems) {
            Remove-Item -Path $DbPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Save-Reminders {
    param($Data)
    $Data | ConvertTo-Json -Depth 3 | Out-File -FilePath $DbPath -Encoding utf8 -Force
}

function Load-Reminders {
    if (Test-Path $DbPath) {
        $Content = Get-Content -Path $DbPath -Raw -ErrorAction SilentlyContinue
        if ($Content) { 
            $Result = ConvertFrom-Json -InputObject $Content
            if ($Result) { return @($Result) }
        }
    }
    return @()
}

$Global:RemindersList = Load-Reminders
$ConsoleHandle = [VolumeHelper]::GetConsoleWindow()

# Функция обновления списка задач на экране GUI
function Update-GuiList {
    if ($Global:ListBox) {
        $Global:ListBox.Items.Clear()
        
        $ActiveTasks = @($Global:RemindersList | Where-Object { [string]$_.Active -match 'true' })
        if ($ActiveTasks.Count -gt 0) {
            foreach ($Task in $ActiveTasks) {
                $TaskTime = $null
                try {
                    $TaskTime = [DateTime]::ParseExact($Task.TargetTime, "dd.MM.yyyy HH:mm", $null)
                    
                } catch {
                  try {
                    $TaskTime = [DateTime]$Task.TargetTime  
                  } catch { $TaskTime = Get-Date }
                }
                $RepeatInfo = if ($Task.RepeatType -eq "Minutes") { "Повтор: каждые $($Task.RepeatInterval) мин." } elseif ($Task.RepeatType -eq "Daily") { "Повтор: ежедневно" } elseif ($Task.RepeatType -eq "Weekly") { "Повтор: еженедельно" } else { "Без повтора" }
                $Global:ListBox.Items.Add("[$($TaskTime.ToString('dd.MM.yyyy HH:mm'))] $RepeatInfo - $($Task.Text)") | Out-Null
            }
        }
    }
}

# Функция расчета следующего времени для зацикленных задач
function Get-NextRepeatTime {
    param([DateTime]$CurrentTarget, [string]$RepeatType, [int]$Interval)

    $SafeInterval = if ($Interval -match '^\d+$') { [int]$Interval } else { 5 }

    switch ($RepeatType) {
        "Minutes" { return $CurrentTarget.AddMinutes($Interval) }
        "Daily" { return $CurrentTarget.AddDays(1) }
        "Weakly" { return $CurrentTarget.AddDays(7) }
        default { return $CurrentTarget }
    }
}

# --- 1. ГЛАВНОЕ ОКНО УПРАВЛЕНИЯ ---
function Show-MainManagerWindow {

    # Переменная, в которой хранится ссылка на редактируемую задачу
    $Global:CurrentEditingTask = $null

    $Global:MainForm.Text = "Менеджер Напоминаний"
    $Global:MainForm.Size = New-Object System.Drawing.Size(550, 420)
    $Global:MainForm.StartPosition = "CenterScreen"
    $Global:MainForm.BackColor = [System.Drawing.Color]::White
    $Global:MainForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $Global:MainForm.TopMost = $true
    $Global:MainForm.FormBorderStyle = "FixedSingle"

    $LblList = New-Object System.Windows.Forms.Label
    $LblList.Location = New-Object System.Drawing.Point(20, 15)
    $LblList.Size = New-Object System.Drawing.Size(200, 20)
    $LblList.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $LblList.Text = "Текущие активные задачи:"
    $Global:MainForm.Controls.Add($LblList)

    $Global:ListBox = New-Object System.Windows.Forms.ListBox
    $Global:ListBox.Location = New-Object System.Drawing.Point(20, 40)
    $Global:ListBox.Size = New-Object System.Drawing.Size(260, 250)
    $Global:MainForm.Controls.Add($Global:ListBox)

    $Global:ListBox.Add_SelectedIndexChanged({
        if ($Global:ListBox.SelectedIndex -ge 0) {
            $SelIdx = $Global:ListBox.SelectedIndex

            # Получаем список активных задач
            $ActiveTasks = @($Global:RemindersList | Where-Object { $_.Active -eq $true })
            $Global:CurrentEditingTask = $ActiveTasks[$SelIdx]

            # Разбираем дату и время из выбранной задачи
            if ($Global:CurrentEditingTask.TargetTime) {
                try {
                    # Принудительно разбиваем строку по нашему шаблону
                    $Global:MainDatePicker.Value = [DateTime]::ParseExact($Global:CurrentEditingTask.TargetTime, "dd.MM.yyyy HH:mm", $null) # Поле даты
                    $Global:MainTimeInput.Text = $Global:MainDatePicker.Value.ToString("HH:mm") # Поле времени
                } catch {
                    # На случай, если в файле будет совсем испорченная строка, ставим текущее время
                    $Global:MainDatePicker.Value = Get-Date
                    $Global:MainTimeInput.Text = (Get-Date).ToString("HH:mm")
                }
            }

            # Заполняем текст и режим повторения
            $Global:MainTextInput.Text = $Global:CurrentEditingTask.Text
            $Global:MainRepeatCombo.SelectedItem = $Global:CurrentEditingTask.RepeatType

            # Находим нужный тип повтора в ComboBox
            switch ($Global:CurrentEditingTask.RepeatType) {
                "None" { $Global:MainRepeatCombo.SelectedIndex = 0 }
                "Minutes" { $Global:MainRepeatCombo.SelectedIndex = 1 }
                "Daily" { $Global:MainRepeatCombo.SelectedIndex = 2 }
                "Weekly" { $Global:MainRepeatCombo.SelectedIndex = 3 }
            }

            # Меняем текст кнопки на "Сохранить изменения"
            $Global:BtnAdd.Text = "[x] Сохранить изменения"
        } else {
            # Если выбор снят - сбрасываем поля в исходное состояние создания
            $Global:CurrentEditingTask = $null
            $Global:MainDatePicker.Value = [DateTime]::Now
            $Global:MainTimeInput.Text = ""
            $Global:MainTextInput.Text = ""
            $Global:MainRepeatCombo.SelectedIndex = 0
            $Global:BtnAdd.Text = "➕ Добавить в список"
        }
    })

    # Создаем объект для всплывающих подсказок
    $Global:ListBoxToolTip = New-Object System.Windows.Forms.ToolTip
    $Global:LastHoveredIndex = -1

    # Добавляем отслеживание движения мыши
    $Global:ListBox.Add_MouseMove({
    
        # Определяем координаты курсора внутри списка
        $MousePoint = $Global:ListBox.PointToClient([System.Windows.Forms.Control]::MousePosition)
        $HoveredIndex = $Global:ListBox.IndexFromPoint($MousePoint)

        # Проверяем, находится ли мышь над реальным элементом списка
        if ($HoveredIndex -ge 0 -and $HoveredIndex -lt $Global:ListBox.Items.Count) {
            # Если мышь переместилась на новый элемент, обновляем подсказку
            if ($HoveredIndex -ne $Global:LastHoveredIndex) {
                $Global:LastHoveredIndex = $HoveredIndex
                $FullText = $Global:ListBox.Items[$HoveredIndex].ToString()

                # Привязываем текст элемента к подсказке списка 
                $Global:ListBoxToolTip.SetToolTip($Global:ListBox, $FullText)
            }
        } else {
            # Если курсор вышел за пределы элементов, очищаем подсказку
            $Global:ListBoxToolTip.SetToolTip($Global:ListBox, "")
            $Global:LastHoveredIndex = -1
        }
    })

    $BtnDelete = New-Object System.Windows.Forms.Button
    $BtnDelete.Location = New-Object System.Drawing.Point(20, 300)
    $BtnDelete.Size = New-Object System.Drawing.Size(260, 30)
    $BtnDelete.Text = "❌ Удалить выбранное напоминание"
    $BtnDelete.Cursor = [System.Windows.Forms.Cursors]::Hand
    $BtnDelete.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $BtnDelete.FlatAppearance.BorderColor = [System.Drawing.Color]::DeepSkyBlue
    $BtnDelete.BackColor = [System.Drawing.Color]::White
    $BtnDelete.FlatAppearance.BorderSize = 3

    $BtnDelete.Add_Click({
        if ($Global:ListBox.SelectedIndex -ge 0 -and $Global:RemindersList.Count -gt 0) {
            $SelIdx = $Global:ListBox.SelectedIndex

            if ($SelIdx -ge 0 -and $Global:RemindersList.Count -gt 0) {
                $Global:RemindersList = Load-Reminders
                $ActiveTasks = @($Global:RemindersList | Where-Object { $_.Active -eq $true })

                if ($SelIdx -lt $ActiveTasks.Count) {
                    $TaskToDelete = $ActiveTasks[$SelIdx]

                    for ($i = 0; $i -lt $Global:RemindersList.Count; $i++){
                        if ($Global:RemindersList[$i].Id -eq $TaskToDelete.Id) {
                            $Global:RemindersList[$i].Active = $false
                            break
                        }
                    }
                Save-Reminders -Data $Global:RemindersList
                Update-GuiList
                }
            }
        }                    
    })
    $Global:MainForm.Controls.Add($BtnDelete)

    $LblAdd = New-Object System.Windows.Forms.Label
    $LblAdd.Location = New-Object System.Drawing.Point(300, 15)
    $LblAdd.Size = New-Object System.Drawing.Size(200, 20)
    $LblAdd.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $LblAdd.Text = "Новое напоминание:"
    $Global:MainForm.Controls.Add($LblAdd)

    $LblDate = New-Object System.Windows.Forms.Label
    $LblDate.Location = New-Object System.Drawing.Point(300, 40)
    $LblDate.Text = "Выбрать дату:"
    $Global:MainForm.Controls.Add($LblDate)

    $Global:MainDatePicker = New-Object System.Windows.Forms.DateTimePicker
    $Global:MainDatePicker.Location = New-Object System.Drawing.Point(300, 65)
    $Global:MainDatePicker.Size = New-Object System.Drawing.Size(200, 25)
    $Global:MainDatePicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $Global:MainDatePicker.CustomFormat = "dd.MM.yyyy"
    $Global:MainForm.Controls.Add($Global:MainDatePicker)

    $LblTime = New-Object System.Windows.Forms.Label
    $LblTime.Location = New-Object System.Drawing.Point(300, 100)
    $LblTime.Size = New-Object System.Drawing.Size(200, 15)
    $LblTime.Text = "Выбрать время (ЧЧ:ММ):"
    $Global:MainForm.Controls.Add($LblTime)

    $Global:MainTimeInput = New-Object System.Windows.Forms.TextBox
    $Global:MainTimeInput.Location = New-Object System.Drawing.Point(300, 120)
    $Global:MainTimeInput.Size = New-Object System.Drawing.Size(70, 25)
    $Global:MainTimeInput.Text = (Get-Date).AddMinutes(10).ToString("HH:mm")
    $Global:MainForm.Controls.Add($Global:MainTimeInput)

    # ВЫБОР ПОВТОРА
    $LblRepeat = New-Object System.Windows.Forms.Label
    $LblRepeat.Location = New-Object System.Drawing.Point(300, 145)
    $LblRepeat.Size = New-Object System.Drawing.Size(200, 15)
    $LblRepeat.Text = "Повторение задачи"
    $Global:MainForm.Controls.Add($LblRepeat)

    $Global:MainRepeatCombo = New-Object System.Windows.Forms.ComboBox
    $Global:MainRepeatCombo.Location = New-Object System.Drawing.Point(300, 170)
    $Global:MainRepeatCombo.Size = New-Object System.Drawing.Size(130, 25)
    $Global:MainRepeatCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$Global:MainRepeatCombo.Items.AddRange(@("Нет", "Минуты", "Ежедневно", "Еженедельно"))
    $Global:MainRepeatCombo.SelectedIndex = 0
    $Global:MainForm.Controls.Add($Global:MainRepeatCombo)
    
    $Global:MainRepeatInterval = New-Object System.Windows.Forms.TextBox
    $Global:MainRepeatInterval.Location = New-Object System.Drawing.Point(440, 170)
    $Global:MainRepeatInterval.Size = New-Object System.Drawing.Size(40, 20)
    $Global:MainRepeatInterval.Text = "5"
    $Global:MainRepeatInterval.Visible = $false
    $Global:MainForm.Controls.Add($Global:MainRepeatInterval)

    $Global:MainRepeatLabelMin = New-Object System.Windows.Forms.Label
    $Global:MainRepeatLabelMin.Location = New-Object System.Drawing.Point(485, 170)
    $Global:MainRepeatLabelMin.Size = New-Object System.Drawing.Size(40, 20)
    $Global:MainRepeatLabelMin.Text = "мин."
    $Global:MainRepeatLabelMin.Visible = $false
    $Global:MainForm.Controls.Add($Global:MainRepeatLabelMin)

    $Global:MainRepeatCombo.Add_SelectedIndexChanged({
        if ($Global:MainRepeatCombo.SelectedIndex -eq 1) {
            $Global:MainRepeatInterval.Visible = $true
            $Global:MainRepeatLabelMin.Visible = $true
        } else {
            $Global:MainRepeatInterval.Visible = $false
            $Global:MainRepeatLabelMin.Visible = $false
        }
    })

    $LblText = New-Object System.Windows.Forms.Label
    $LblText.Location = New-Object System.Drawing.Point(300, 200)
    $LblText.Size = New-Object System.Drawing.Size(200, 15)
    $LblText.Text = "Текст напоминания:"
    $Global:MainForm.Controls.Add($LblText)

    $Global:MainTextInput = New-Object System.Windows.Forms.TextBox
    $Global:MainTextInput.Location = New-Object System.Drawing.Point(300, 220)
    $Global:MainTextInput.Size = New-Object System.Drawing.Size(200, 25)
    $Global:MainTextInput.Text = "Новая задача"
    $Global:MainForm.Controls.Add($Global:MainTextInput)

    $Global:BtnAdd = New-Object System.Windows.Forms.Button
    $Global:BtnAdd.Location = New-Object System.Drawing.Point(300, 250)
    $Global:BtnAdd.Size = New-Object System.Drawing.Size(200, 35)
    
    # Проверяем, запущена ли форма в режиме редактирования прямо сейчас
    if ($null -ne $Global:CurrentEditingTask) {
        $Global:BtnAdd.Text = "[x] Сохранить изменения"
    } else {
        $Global:BtnAdd.Text = "➕ Добавить в список"
    }
    $Global:BtnAdd.BackColor = [System.Drawing.Color]::FromArgb(240, 244, 248)
    $Global:BtnAdd.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Global:BtnAdd.Add_Click({
        $CleanTime = ("" + $Global:MainTimeInput.Text).Trim()
        if ($CleanTime -match '^(\d{1,2}):(\d{2})$') {
            $TimeParts = $CleanTime.Split(':')
            $Hours   = [int]($TimeParts[0])
            $Minutes = [int]($TimeParts[1])

            $Year  = $Global:MainDatePicker.Value.Year
            $Month = $Global:MainDatePicker.Value.Month
            $Day   = $Global:MainDatePicker.Value.Day

            # Изолированный разбор даты во избежание сдвига часовых поясов Windows
            $FinalTarget = [DateTime]"$Year-$Month-$Day ${Hours}:${Minutes}:00"
            $TimeDifferenceInSeconds = ($FinalTarget - (Get-Date)).TotalSeconds

            if ($TimeDifferenceInSeconds -lt -10) {
                [System.Windows.Forms.MessageBox]::Show("Вы ввели время в прошлом!", "Внимание", "OK", "Warning") | Out-Null
                return
            }
            
            $Txt = if ([string]::IsNullOrWhiteSpace($Global:MainTextInput.Text)) { "Напоминание" } else { $Global:MainTextInput.Text }

            # Сбор параметров повтора
            $RepeatType = "None"
            if ($Global:MainRepeatCombo.SelectedIndex -eq 1) { $RepeatType = "Minutes" }
            if ($Global:MainRepeatCombo.SelectedIndex -eq 2) { $RepeatType = "Daily" }
            if ($Global:MainRepeatCombo.SelectedIndex -eq 3) { $RepeatType = "Weekly" }

            $Interval = if ($Global:MainRepeatInterval.Text -match '^\d+$') { [int]$Global:MainRepeatInterval.Text } else { 5 }
            
            # Разделение логики: Редактирование или создание
            if ($null -ne $Global:CurrentEditingTask) {
                # Режим редактирования существующей задачи
                for ($i = 0; $i -lt $Global:RemindersList.Count; $i++) {
                    if ($Global:RemindersList[$i].Id -eq $Global:CurrentEditingTask.Id) {
                        $Global:RemindersList[$i].TargetTime = $FinalTarget.ToString('dd.MM.yyyy HH:mm')
                        $Global:RemindersList[$i].Text = $Txt
                        $Global:RemindersList[$i].RepeatType = $RepeatType
                        $Global:RemindersList[$i].RepeatInterval = $Interval
                        break
                    }
                }
                # Сбрасываем переменную редактирования и возвращаем исходный текст кнопке
                $Global:CurrentEditingTask = $null
                $Global:BtnAdd.Text = "➕ Добавить в список"
            } else {
                # Режим создания новой задачи
                $NewTask = [guid]::NewGuid().ToString() 
                $TargetTime = $FinalTarget.ToString('dd.MM.yyyy HH:mm')
                $Text = $Txt
                $Active = $true
                $RepeatType = $RepeatType
                $RepeatInterval = $Interval 
            
                $Global:RemindersList += @([PSCustomObject]@{
                  Id = $NewTask
                  TargetTime = $TargetTime
                  Text = $Text
                  Active = $Active
                  RepeatType = $RepeatType
                  RepeatInterval = $RepeatInterval
                  })
            }
            # Сохранение изменений, обновление интерфейса и очистка полей
            Save-Reminders -Data $Global:RemindersList
            Update-GuiList

            $Global:MainTextInput.Text = ""
            $Global:MainTimeInput.Text = ""
            $Global:ListBox.SelectedIndex = -1 # Снимаем выделение со списка задач
        } else {
            [System.Windows.Forms.MessageBox]::Show("Неверный формат времени! Используйте ЧЧ:ММ", "Ошибка", "OK", "Error") | Out-Null
        }
    })
    $Global:MainForm.Controls.Add($Global:BtnAdd)

    $BtnMonitor = New-Object System.Windows.Forms.Button
    $BtnMonitor.Location = New-Object System.Drawing.Point(300, 300)
    $BtnMonitor.Size = New-Object System.Drawing.Size(200, 30)
    $BtnMonitor.Text = "🔔 Свернуть в Трей"
    $BtnMonitor.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $BtnMonitor.ForeColor = [System.Drawing.Color]::White
    $BtnMonitor.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $BtnMonitor.Cursor = [System.Windows.Forms.Cursors]::Hand
    $BtnMonitor.Add_Click({
        $Global:StartMonitoring = $true
        $Global:MainForm.Hide()
    })
    $Global:MainForm.Controls.Add($BtnMonitor)

    $Global:MainForm.Add_Load({
        Update-GuiList
    })
}

# --- 2. БЛОК ИКОНКИ В СИСТЕМНОМ ТРЕЕ ---
$TrayIcon = New-Object System.Windows.Forms.NotifyIcon
$TrayIcon.Icon = [System.Drawing.SystemIcons]::Information
$TrayIcon.Visible = $true

$TrayIcon.Add_Click({
    param($sender, $e)

if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
    if ($Global:MainForm.Visible) {
        $Global:MainForm.Hide()
    } else {
        $Global:StartMonitoring = $false

        $Global:RemindersList = Load-Reminders

        Update-GuiList
        [void]$Global:MainForm.ShowDialog()
    }
}
})

$ContextMenu = New-Object System.Windows.Forms.ContextMenu
$ExitMenuItem = New-Object System.Windows.Forms.MenuItem("Выйти из планировщика")
$Global:AbortTimer = $false
$ExitMenuItem.Add_Click({
    $Global:AbortTimer = $true
    $Global:MainForm.Close()
})
$ContextMenu.MenuItems.Add($ExitMenuItem) | Out-Null
$TrayIcon.ContextMenu = $ContextMenu

#Функция вызова асинхронных окон карточек напоминаний
function Show-NotificationWindow {
    param($TaskId, $CurrentText, $CurrentTargetTime)
    $Form = New-Object System.Windows.Forms.Form
    $Form.Size = New-Object System.Drawing.Size(420, 260)
    $Form.StartPosition = "Manual"
    $Form.FormBorderStyle = "None"
    $Form.TopMost = $true
    $Form.BackColor = [System.Drawing.Color]::White
    
    $RandomOffset = Get-Random -Minimum 0 -Maximum 40
    $Screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $Form.Left = $Screen.Width - $Form.Width - 15 - $RandomOffset
    $Form.Top = $Screen.Height - $Form.Height - 15 - $RandomOffset

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
    $MessageLabel.Text = $CurrentText
    $Form.Controls.Add($MessageLabel)
    
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
    
    # КНОПКА ПЕРЕНЕСТИ
    $SnoozeButton = New-Object System.Windows.Forms.Button
    $SnoozeButton.Location = New-Object System.Drawing.Point(110, 195)
    $SnoozeButton.Size = New-Object System.Drawing.Size(140, 40)
    $SnoozeButton.Text = "Перенести"
    $SnoozeButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $SnoozeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $SnoozeButton.FlatAppearance.BorderSize = 1
    $SnoozeButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $SnoozeButton.BackColor = [System.Drawing.Color]::White
    $SnoozeButton.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $SnoozeButton.Tag = $Form
    $SnoozeButton.Add_Click({
        $NewTargetTime = (Get-Date).AddMinutes(5)
        if ($RadioTime.Checked) {
            $CleanTimeText = ("" + $SnoozeTimeInput.Text).Trim()
            if ($CleanTimeText -match '^\d{1,2}:\d{2}$') {
                $TimeParts = $CleanTimeText.Split(':')
                $NewHours = [int]($TimeParts[0])
                $NewMinutes = [int]($TimeParts[1])
                
                $SelectedDate = $SnoozeDatePicker.Value.ToString("dd.MM.yyyy")
                $BaseDate = [DateTime]::ParseExact($SelectedDate, "dd.MM.yyyy", $null)
                $NewTargetTime = Get-Date $BaseDate -Hour $NewHours -Minute $NewMinutes -Second 0
                if (($NewTargetTime - (Get-Date)).TotalMinutes -lt -1) { $NewTargetTime = $NewTargetTime.AddDays(1) }
            }
        } else {
            $MinText = ("" + $SnoozeInput.Text).Trim()
            $MinVal = if ($MinText -match '^\d+$') { [int]$MinText } else { 5 }
            $NewTargetTime = (Get-Date).AddMinutes($MinVal)
        }
        
        $TaskToUpdate = $Global:RemindersList | Where-Object { $_.Id -eq $TaskId }
        $OldList = Load-Reminders
        $NewList = @()

        foreach ($Task in $OldList) {
            if ($Task.Id -eq $TaskId) {
                $Task.TargetTime = $NewTargetTime.ToString("o")
                $Task.Active = [bool]$true
                #$Task.RepeatType = "None"                 
            }
            $NewList += $Task
        }
        $Global:RemindersList = $NewList
        Save-Reminders -Data $Global:RemindersList

        # Удаляем ID задачи из списка открытых окон, освобождая поток 
        $Global:OpenNotifications.Remove($TaskId)

        Update-GuiList
        $Form.Close()
        
    })
    $Form.Controls.Add($SnoozeButton)
    
    # КНОПКА ПОНЯТНО
    $CloseButton = New-Object System.Windows.Forms.Button
    $CloseButton.Location = New-Object System.Drawing.Point(280, 195)
    $CloseButton.Size = New-Object System.Drawing.Size(115, 40)
    $CloseButton.Text = "Понятно"
    $CloseButton.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $CloseButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $CloseButton.ForeColor = [System.Drawing.Color]::White
    $CloseButton.Tag = $Task # передаем объект текущей задачи
    $CloseButton.Add_Click({
        
        $OldList = Load-Reminders
        # Получаем именно ту задачу, которая привязана к этой конкретной кнопке
        $CurrentTask = $this.Tag

        $NewList = @()
       
        foreach ($Task in $OldList) {               
            if ($Task.Id -eq $TaskId) {                
                    if ($null -ne $CurrentTask.RepeatType -and $CurrentTask.RepeatType -ne "None" -and $CurrentTask.RepeatType -ne "") {
                    
                        $OldTarget = [DateTime]$CurrentTask.TargetTime
                    
                        # Если у задачи есть циклический повтор - рассчитываем следующее время
                        $RightNow = Get-Date
                        #$NextTime = Get-NextRepeatTime -CurrentTarget $OldTarget -RepeatType $Task.RepeatType -Interval [int]$Task.RepeatInterval

                        # Защита от образования мертвой петли, если время ушло далеко назад
                        #while ($NextTime -le (Get-Date).AddSeconds(5)) {
                        #    $NextTime = Get-NextRepeatTime -CurrentTarget $NextTime -RepeatType $Task.RepeatType -Interval [int]$Task.RepeatInterval
                        #}
                        $UpdateTask = [PSCustomObject]@{
                            Id = $Task.Id
                            TargetTime = $NextTime.ToString("o")
                            Text = $TaskText
                            Active = [bool]$true
                            RepeateType = $CurrentTask.RepeatType
                            RepeatInterval = $CurrentTask.RepeatInterval
                        }
                        $NewList += $UpdateTask
                    } else {
                        $Task.Active = [bool]$false
                        $NewList += $Task
                    }
            } else {
                $NewList += $Task
            }
        }
        $Global:RemindersList = $NewList
        if ($CurrentTask.RepeatType -eq "None") { Save-Reminders -Data $Global:RemindersList }

                
        # Удаляем ID задачи из списка открытых окон, освобождая поток 
        $Global:OpenNotifications.Remove($TaskId)

        Update-GuiList
        $Form.Close()
        
    })
    $Form.Controls.Add($CloseButton)
    
    $Form.Padding = New-Object System.Windows.Forms.Padding(1)
    $Form.Add_Paint({
        param($sender, $e)
        $Pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(218, 218, 218), 1)
        $e.Graphics.DrawRectangle($Pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
    })
    # Запускаем карточку через модальный ShowDialog().
    [void]$Form.ShowDialog()
    $Form.Dispose()
    #$Form.Show()
}

#--- СИНХРОННЫЙ СТАРТ ГЛАВНОГО ОКНА ---
$Global:MainForm = New-Object System.Windows.Forms.Form
Show-MainManagerWindow
$Global:MainForm.Add_FormClosing({
    param($sender, $e)
    if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
        $e.Cancel = $true
        $Global:StartMonitoring = $true
        $Global:MainForm.Hide()
    }
})
if ($ConsoleHandle -eq [IntPtr]::Zero -or $ConsoleHandle -eq 0) { $ConsoleHandle = (Get-Process -Id $PID).MainWindowHandle }
[void][VolumeHelper]::ShowWindow($ConsoleHandle, 0)
$Global:StartMonitoring = $false
[void]$Global:MainForm.ShowDialog()
if (-not $Global:StartMonitoring) {
    $TrayIcon.Visible = $false
    $TrayIcon.Dispose()
    Exit
}

# Список для отслеживания открытых окон, чтобы они не плодились
$Global:OpenNotifications = @{}

#--- БЕСКОНЕЧНЫЙ ЦИКЛ ФОНОВОГО МОНИТОРИНГА ЗАДАЧ С АВТОПОВТОРОМ ---
while ($true) {
    if ($Global:AbortTimer) { break }
    # Поддерживаем фоновую работу системного трея Windows
    [System.Windows.Forms.Application]::DoEvents()
    
    $Global:RemindersList = Load-Reminders
    $CurrentActiveTasks = @($Global:RemindersList | Where-Object { [string]$_.Active -match 'true' })
    
    if ($CurrentActiveTasks.Count -eq 0) {
        $TrayIcon.Text = "Менеджер напоминаний`nНет активных задач"
        Start-Sleep -Milliseconds 250
        continue
    }
    
    $MinSeconds = 99999999
    $ClosestTaskText = ""
    
    foreach ($Task in $CurrentActiveTasks) {
        try {
            $TaskTime = [DateTime]::ParseExact($Task.TargetTime, "dd.MM.yyyy HH:mm", $null)
            $SecLeft = [int]($TaskTime - (Get-Date)).TotalSeconds
        } catch { $SecLeft = 0 }
        if ($SecLeft -le 0) {
            # Если окно для этой задачи уже открыто - просто пропускаем шаг
            if ($Global:OpenNotifications.Contains($Task.Id)) { continue }

            # Регистрируем окно в списке открытых
            $Global:OpenNotifications[$Task.Id] = $true

            # Если это повтор, сразу сдвигаем его в памяти от текущей секунды вперед,
            # чтобы карточка спокойно висела на экране, а трей уже считал новое чистое будущее время!
            if ($null -ne $Task.RepeatType -and $Task.RepeatType -ne "None") {
                $RightNow = Get-Date
                $NextTime = Get-NextRepeatTime -CurrentTarget $RightNow -RepeatType $Task.RepeatType -Interval $Task.RepeatInterval
                while ($NextTime -le (Get-Date).AddSeconds(10)) {
                    $NextTime = Get-NextRepeatTime -CurrentTarget $NextTime -RepeatType $Task.RepeatType -Interval $Task.RepeatInterval
                }
                $Task.TargetTime = $NextTime.ToString("o")
            }

            Save-Reminders -Data $Global:RemindersList

            # Стабильный встроенный бип вместо вешающего систему голоса
            try { [System.Media.SystemSounds]::Hand.Play() } catch {}
            
            # Запускаем карточку
            Show-NotificationWindow -TaskId $Task.Id -CurrentText $Task.Text -CurrentTargetTime $Task.TargetTime
            continue
        }
        if ($SecLeft -lt $MinSeconds) {
            $MinSeconds = $SecLeft
            $ClosestTaskText = $Task.Text
        }
    }
    
    if ($MinSeconds -lt 99999999) {
        if ($MinSeconds -gt 3600) {
            $TrayTimeStr = "$([Math]::Floor($MinSeconds / 3600)) ч. $([Math]::Floor(($MinSeconds % 3600) / 60)) м."
        } else {
            $TrayTimeStr = "$([Math]::Floor($MinSeconds / 60)) мин. $($MinSeconds % 60) сек."
        }
        $SafeText = $ClosestTaskText
        if ($SafeText.Length -gt 20) { $SafeText = $SafeText.Substring(0, 17) + "..." }
        $TrayIcon.Text = "Ближайшая через: $TrayTimeStr`nЗадача: $SafeText"
    }
    Start-Sleep -Milliseconds 250
}

$TrayIcon.Visible = $false
$TrayIcon.Dispose()
[void][VolumeHelper]::ShowWindow($ConsoleHandle, 9)
