@echo off
rem Runs the character-select probe INSTEAD of the training script.
rem Find which byte says a player has locked in when that player is Bulleta.
rem   1. reach the character select screen
rem   2. choose BULLETA on P1 and lock in, wait a second
rem   3. choose anyone on P2 and lock in, wait a second
rem   4. do it again with DEMITRI on P1, as a working case to compare
rem Then close the emulator. The log lands next to fcadefbneo.exe.
cd /d "%~dp0.." || exit /b 1
start "" "%cd%\fcadefbneo.exe" vsavj savestates\vsavj_fbneo.fs analysis\selectProbe.lua
exit /b
