@Echo Off

chcp 65001 > nul

mode con: cols=80 lines=10

set "scriptPath=f:\wps\UpdatesCopy_server002.ps1"

IF NOT EXIST "%scriptPath%" (
	echo Ошибка: Файл скрипта PowerShell не найден по пути: "%scriptPath%"
	pause
	exit /b
)

powershell.exe -ExecutionPolicy Bypass -File "%scriptPath%"

pause