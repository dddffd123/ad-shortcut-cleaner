@echo off
chcp 65001 >nul
title Secret Cleaner
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleaner.ps1" %*
