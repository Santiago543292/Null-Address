@echo off
REM ===========================================================================
REM  Null Address - AI launcher
REM
REM  Double-click this to talk to the QX++ level architect.
REM
REM  Do NOT run level_architect.QX+ directly: the C++ interpreter (qxpp.exe)
REM  crashes on it ("std::out_of_range: stoi: out of range") and, even when it
REM  does not crash, its `if` bodies never assign, so every branch is wrong.
REM  This launcher uses the Python interpreter, which handles it correctly.
REM ===========================================================================

title Null Address - AI

cd /d "%~dp0"

echo.
echo  Looking for Python...
where python >nul 2>nul
if errorlevel 1 goto nopython

python run_ai.py
goto end

:nopython
where python3.11 >nul 2>nul
if errorlevel 1 goto nopython2
python3.11 run_ai.py
goto end

:nopython2
echo.
echo  Python was not found on PATH.
echo  Install Python 3.11+ from https://python.org and try again.
echo.

:end
echo.
pause
