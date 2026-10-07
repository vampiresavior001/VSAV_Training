@echo off
rem Stand in this file's own folder before anything else.
rem
rem The start line depends on it: %cd% builds the path of fcadefbneo.exe, and
rem the savestate and the script are relative to it. A double click already starts
rem here, so nothing changes there - but calling the file by its full path from
rem somewhere else used to fail with "fcadefbneo.exe was not found", which says
rem nothing about the actual cause. The probe launchers under analysis\ have
rem always done this.
rem
rem The exe is quoted, and the "" after start is the window title: start
rem takes its first quoted argument as one, which would swallow the exe.
rem THE ARGUMENTS ARE NOT QUOTED. fcadefbneo.exe does not read quoted
rem arguments: "savestates\vsavj_fbneo.fs" arrived as savestates\vsavj_fbneo.f
rem and was refused (2026-10-07). So they are RELATIVE, which keeps the
rem spaces of the folder out of them: from "space test (x86)\fbneo" the game
rem and the script both loaded, and the script still ran in scripts\ - it
rem found its images there and wrote training_data\ beside it (2026-10-07).
rem If the cd fails nothing is started. exit /b, not exit: called from a
rem console, a bare exit closed it.
cd /d "%~dp0" || exit /b 1
echo STARTING Training Mode for VSAV
echo Make sure you have vsavj.zip in the 'roms' folder
start "" "%cd%\fcadefbneo.exe" vsavj savestates\vsavj_fbneo.fs scripts\vsav_training_master_script.lua
exit /b
