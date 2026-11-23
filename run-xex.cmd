@echo off
setlocal
set "ALTIRRA=C:\Users\barto\Altirra-4.31\Altirra64.exe"
if "%~1"=="" (
    echo Brak pliku XEX do uruchomienia.
    exit /b 1
)
"%ALTIRRA%" /run "%~1"
