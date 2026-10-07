@echo off
rem Runs the keyboard probe INSTEAD of the training script.
rem Can Lua read the PC keyboard on this emulator? It decides how
rem Action Patterns can be shared.
rem   1. press a few letters, then Enter / Backspace / Shift
rem   2. type a short word and see whether every letter lands
cd /d "%~dp0.." || exit /b 1
start "" "%cd%\fcadefbneo.exe" vsavj savestates\vsavj_fbneo.fs analysis\keyboardProbe.lua
exit /b
