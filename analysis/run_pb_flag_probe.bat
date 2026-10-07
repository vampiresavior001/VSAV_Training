@echo off
rem Runs the PB flag probe INSTEAD of the training script.
rem "PB Count: 0" was drawn GREEN, which says granted-with-no-presses.
rem   1. guard an attack and mash to push block. Several times, including
rem      attempts you do not complete.
rem   2. watch the anomaly count - it rises when lua=0 and ok=true together.
rem   3. let the round end, start another, push block again.
rem lua is the count this probe keeps the way timers.lua keeps it, game $170
rem is the game's own count. They should move together.
cd /d "%~dp0.." || exit /b 1
start "" "%cd%\fcadefbneo.exe" vsavj savestates\vsavj_fbneo.fs analysis\pbFlagProbe.lua
exit /b
