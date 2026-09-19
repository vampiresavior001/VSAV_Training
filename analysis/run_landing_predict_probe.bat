@echo off
rem Runs the landing prediction probe INSTEAD of the training script.
rem Question: does ticks_to_landing() actually predict the touchdown, and how
rem far ahead can its answer be trusted?
rem
rem Why it matters: to put a dash out on the first actionable tick after
rem landing, the input list has to START several ticks earlier - a gate that
rem only reacts to the landing is already too late by that much.
rem
rem What to do:
rem   Play Sasquatch on 1P. Forward dash (a hop for her), cancel into a light
rem   attack, land. Ten or fifteen times. Ordinary jumps count too, and the
rem   dummy's jumps are measured as well.
rem
rem What to look for:
rem   "err" on screen is predicted minus actual, across every prediction made
rem   during every descent. "+0" only means the prediction is exact.
rem Everything also lands in analysis\landing_predict_probe.log.
cd /d "%~dp0.."
start fcadefbneo.exe vsavj savestates\vsavj_fbneo.fs %cd%\analysis\landingPredictProbe.lua
exit
