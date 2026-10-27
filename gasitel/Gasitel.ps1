param($minutes = 1200)
$myshell = New-Object -com "WScript.Shell"
for ($i = 0; $i -lt $minutes; $i++) {
  Start-Sleep -Seconds 180
  $myshell.sendkeys("{SCROLLLOCK}")
}