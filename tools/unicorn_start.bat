@echo off
rem Double-click to connect the g.tec Unicorn Hybrid Black to the game.
rem Needs Python 3, Unicorn Suite Hybrid Black with a license, and the headset
rem paired over Bluetooth. Extra arguments are passed on, e.g. --debug.
chcp 65001 >nul
set PYTHONIOENCODING=utf-8
cd /d "%~dp0"
where py >nul 2>nul && (set "PY=py -3") || (set "PY=python")
%PY% -c "import numpy" >nul 2>nul || %PY% -m pip install --disable-pip-version-check numpy
%PY% Neu_to_text_new5.py %*
pause
