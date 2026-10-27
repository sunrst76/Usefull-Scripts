@Echo Off

chcp 65001 > nul

mode con: cols=100 lines=20

set "scriptPath=d:\wps\Updates_Copy_alternate.ps1"

IF NOT EXIST "%scriptPath%" (
	echo Ошибка: Файл скрипта PowerShell не найден по пути: "%scriptPath%"
	pause
	exit /b
)

powershell.exe -ExecutionPolicy Bypass -File "%scriptPath%"

pause