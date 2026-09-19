@echo off
rem Runs the file dialog probe INSTEAD of the training script.
rem Question: can the tool open a native Save/Open dialog through PowerShell,
rem move the file, and come out of it still running?
rem
rem The dialog, the freeze and the ASCII round trip already passed on
rem 2026-09-16. Two cases are left, and both need a human:
rem   Lua Hotkey 2  Export INTO A FOLDER WITH JAPANESE IN THE PATH - the
rem                 Desktop will do. Lua never opens that path (it cannot),
rem                 so this is really asking whether PowerShell's copy lands.
rem   Lua Hotkey 2  again, this time pressing CANCEL. Expected: the log says
rem                 "cancelled (not a fault)" and nothing else happens.
rem   Lua Hotkey 3  Import the file the Japanese-folder save wrote.
rem Hotkey 1 is plain io.popen with no dialog; it already passed, skip it.
rem Keep playing for a few seconds after each one: whether the emulator comes
rem back matters as much as whether the dialog worked.
rem Everything also lands in analysis\dialog_probe.log (FBNeo resolves relative
rem io.open against the Lua script's own folder, not this bat's cd target).
cd /d "%~dp0.."
start fcadefbneo.exe vsavj savestates\vsavj_fbneo.fs %cd%\analysis\dialogProbe.lua
exit
