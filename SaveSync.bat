@echo off
rem Abre el menu de save-sync. Doble clic para usarlo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0save-sync.ps1" %*
