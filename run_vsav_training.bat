@echo off
rem Stand in this file's own folder before anything else.
rem
rem Both lines below depend on it: fcadefbneo.exe is named without a path, and
rem %cd% builds the path handed to the emulator. A double click already starts
rem here, so nothing changes there - but calling the file by its full path from
rem somewhere else used to fail with "fcadefbneo.exe was not found", which says
rem nothing about the actual cause. The probe launchers under analysis\ have
rem always done this.
cd /d "%~dp0"
echo STARTING Training Mode for VSAV
echo Make sure you have vsavj.zip in the 'roms' folder
start fcadefbneo.exe vsavj savestates\vsavj_fbneo.fs %cd%\scripts\vsav_training_master_script.lua
exit
