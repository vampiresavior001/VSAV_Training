@echo off
rem Runs the GC success probe INSTEAD of the training script.
rem Question: does the guard cancel come out on the same TICK as the button
rem press or release that completed the command?
rem   1. set the dummy to attack so there is something to block
rem   2. block, then input the guard cancel: DPF (6 2 3) + button
rem   3. do it eight or ten times, including attempts that were too late
rem   4. complete one or two by RELEASING the button instead of pressing it
rem The screen shows the gap in ticks between the last button edge and the
rem cancel. All zeros means the input bar is only losing it to sampling rate.
cd /d "%~dp0.."
start fcadefbneo.exe vsavj savestates\vsavj_fbneo.fs %cd%\analysis\gcSuccessProbe.lua
exit
