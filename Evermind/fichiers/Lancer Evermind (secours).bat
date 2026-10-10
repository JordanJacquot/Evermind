@echo off
rem Lanceur de secours, si Evermind.exe est bloque par l'antivirus.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Evermind.ps1"
