@echo off
rem Runs the lever probe INSTEAD of the training script.
rem Left/Right stopped changing the standing position; down-left and
rem down-right still work. This shows what the lever reads as.
rem   1. hold LEFT alone and read the now line
rem   2. hold DOWN+LEFT, then RIGHT, then DOWN+RIGHT
rem   3. press whatever key you use for the position shortcut. The probe
rem      registers ALL eight Lua hotkeys and shows which index arrived,
rem      so a key mapped to a different index shows up as that number.
cd /d "%~dp0.." || exit /b 1
start "" "%cd%\fcadefbneo.exe" vsavj savestates\vsavj_fbneo.fs analysis\leverProbe.lua
exit /b
