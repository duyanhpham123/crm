@echo off
rem Tao lai file MyERP.sql tu database hien tai (cau truc + toan bo du lieu).
rem Chay truoc khi mang project sang may khac.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0source\export-sql.ps1" -Server localhost -Database MyERP -Output "%~dp0MyERP.sql" || goto :fail
echo.
echo Xong: database\MyERP.sql
pause
exit /b 0

:fail
echo.
echo That bai. Kiem tra SQL Server dang chay va database MyERP co tren may nay.
pause
exit /b 1
