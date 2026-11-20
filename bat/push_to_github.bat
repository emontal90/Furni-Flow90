@echo off
title Push FurniFlow to GitHub
echo ===============================================================
echo          Pushing FurniFlow project to GitHub Repository
echo       Repository: https://github.com/emontal90/Furni-Flow90.git
echo ===============================================================
echo.
cd /d "%~dp0.."
git push -u origin main
echo.
echo ===============================================================
pause
