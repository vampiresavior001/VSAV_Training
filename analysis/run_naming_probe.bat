@echo off
rem Runs the pattern-naming probe INSTEAD of the training script.
rem Question: can an Action Pattern be named from a separate text window?
rem
rem gui.text was measured on 2026-09-16 drawing NOTHING for kana and kanji, so
rem names are ASCII-only and this window is how they get typed. The sample
rem lines at the top of the screen are that evidence, kept on display.
rem
rem   Lua Hotkey 1  type an ASCII name, press Enter - the normal case
rem   Lua Hotkey 2  type a JAPANESE name with the IME - it should come back
rem                 fine and then draw as an empty row. That is what someone
rem                 hits by accident, and it decides whether the real thing
rem                 rejects such a name, strips it, or lets it through
rem   Lua Hotkey 3  rename - the box comes up pre-filled, edit it, press Enter
rem   Lua Hotkey 4  open it and press ESCAPE (the cancel case)
rem
rem After each one the result is drawn back through gui.text, the same path a
rem real pattern name would take. Say what you SEE there, not only what you
rem typed - the two disagreeing is the finding.
rem Everything also lands in analysis\naming_probe.log.
cd /d "%~dp0.."
start fcadefbneo.exe vsavj savestates\vsavj_fbneo.fs %cd%\analysis\namingProbe.lua
exit
