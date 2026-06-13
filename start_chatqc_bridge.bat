@echo off
cd /d "%~dp0"
title ChatQC Bridge - claude -p
echo Demarrage du pont ChatQC (surveille inbox.json et lance claude -p)...
echo Pre-requis : VIM Flex ouvert avec le serveur MCP ON (port 3012).
echo.
py -3 chatqc_bridge.py
pause
