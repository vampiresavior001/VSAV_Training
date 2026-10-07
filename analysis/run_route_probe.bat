@echo off
rem Runs the route probe INSTEAD of the training script. Nothing else is loaded.
rem Once each, with a pause between:
rem   1. jump, and attack in the air
rem   2. dash, and attack out of the dash
rem   3. jump, and land without attacking
rem   4. hit the dummy, then jump in and hit it again while it is still reeling
rem   5. walk forward, walk back, crouch - each on its own
rem   6. attack an opponent that is GUARDING (a CPU opponent blocks on its own)
rem   7. an air dash attack, if the character has one
rem   8. hit a CPU opponent and let it recover on its own, several times
rem   9. rapid-fire LP BY HAND, twice and three times. No menu here, so
rem      Auto is checked in the training script instead.
rem Then close the emulator. The log lands next to fcadefbneo.exe.
cd /d "%~dp0.." || exit /b 1
start "" "%cd%\fcadefbneo.exe" vsavj savestates\vsavj_fbneo.fs analysis\routeProbe.lua
exit /b
