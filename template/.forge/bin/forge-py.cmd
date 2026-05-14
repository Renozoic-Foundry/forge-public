@echo off
rem forge-py.cmd - FORGE cross-platform Python invocation wrapper (Windows)
rem Spec 401. Resolves the first Python >=3.10 from `python3 -> python -> py -3`,
rem falls through on version-floor mismatch, skips the Microsoft Store zero-byte
rem stub at %LOCALAPPDATA%\Microsoft\WindowsApps\python.exe, then runs the script
rem with remaining args. Exits with the script's exit code (or >=1 on no-resolve).
rem
rem Usage: forge-py.cmd <script-path> [args...]

setlocal EnableDelayedExpansion

rem Spec 417: force utf-8 stdout/stderr so non-ASCII helper output does not
rem crash on Windows where Python defaults to cp1252.
set "PYTHONIOENCODING=utf-8"

if "%~1"=="" (
  echo forge-py: usage: forge-py ^<script-path^> [args...] 1>&2
  exit /b 2
)

set "FORGE_PY_FLOOR_MAJOR=3"
set "FORGE_PY_FLOOR_MINOR=10"
set "FORGE_PY_RESOLVED="
set "FORGE_PY_RESOLVED_ARGS="

call :try_candidate "python3" ""
if defined FORGE_PY_RESOLVED goto :run

call :try_candidate "python" ""
if defined FORGE_PY_RESOLVED goto :run

call :try_candidate "py" "-3"
if defined FORGE_PY_RESOLVED goto :run

echo error: no Python interpreter ^>= %FORGE_PY_FLOOR_MAJOR%.%FORGE_PY_FLOOR_MINOR% found on PATH. Install Python 3.10+ from https://www.python.org/downloads/ or via the Microsoft Store. 1>&2
exit /b 1

:run
rem Shift past $1 (script path is preserved separately so we don't have to pre-shift).
rem Use %* and strip the first token.
set "_SCRIPT=%~1"
shift
set "_ARGS="
:collect_args
if "%~1"=="" goto :do_exec
set "_ARGS=!_ARGS! %1"
shift
goto :collect_args
:do_exec
%FORGE_PY_RESOLVED% %FORGE_PY_RESOLVED_ARGS% -X utf8 "%_SCRIPT%"!_ARGS!
exit /b %ERRORLEVEL%

rem -----------------------------------------------------------------
rem :try_candidate <executable-name> <extra-args>
rem Sets FORGE_PY_RESOLVED + FORGE_PY_RESOLVED_ARGS if candidate found and >=floor.
rem -----------------------------------------------------------------
:try_candidate
set "_CAND=%~1"
set "_CAND_ARGS=%~2"

rem Locate via `where`.
for /f "delims=" %%P in ('where %_CAND% 2^>NUL') do (
  set "_PATH=%%P"
  rem Skip Microsoft Store stub: zero-byte file under WindowsApps.
  call :is_ms_store_stub "!_PATH!"
  if errorlevel 1 (
    rem Not a stub; check version floor.
    call :check_floor "!_PATH!" "%_CAND_ARGS%"
    if not errorlevel 1 (
      set "FORGE_PY_RESOLVED=!_PATH!"
      set "FORGE_PY_RESOLVED_ARGS=%_CAND_ARGS%"
      goto :try_candidate_done
    )
  )
)
:try_candidate_done
exit /b 0

rem -----------------------------------------------------------------
rem :is_ms_store_stub <full-path>
rem Returns errorlevel 0 if path is the Microsoft Store stub, 1 otherwise.
rem -----------------------------------------------------------------
:is_ms_store_stub
set "_TESTPATH=%~1"
set "_STORE=%LOCALAPPDATA%\Microsoft\WindowsApps"
echo %_TESTPATH% | findstr /I /C:"%_STORE%" >NUL
if errorlevel 1 exit /b 1
rem Path is under WindowsApps. Treat as stub regardless of size (the alias
rem is unreliable: launches Store rather than running Python).
exit /b 0

rem -----------------------------------------------------------------
rem :check_floor <interpreter-path> <extra-args>
rem Returns errorlevel 0 if interpreter satisfies floor, 1 otherwise.
rem -----------------------------------------------------------------
:check_floor
set "_IP=%~1"
set "_IA=%~2"
for /f "tokens=2 delims= " %%V in ('"%_IP%" %_IA% --version 2^>^&1') do set "_VER=%%V"
if not defined _VER exit /b 1
for /f "tokens=1,2 delims=." %%A in ("%_VER%") do (
  set "_VMAJ=%%A"
  set "_VMIN=%%B"
)
rem Strip non-digit suffix from minor (alpha/beta/rc/+).
set "_VMIN_CLEAN="
for /f "delims=0123456789" %%X in ("%_VMIN%x") do set "_TAIL=%%X"
call set "_VMIN_CLEAN=%%_VMIN:!_TAIL!=%%"
if "%_VMIN_CLEAN%"=="" set "_VMIN_CLEAN=%_VMIN%"
if %_VMAJ% GTR %FORGE_PY_FLOOR_MAJOR% exit /b 0
if %_VMAJ% LSS %FORGE_PY_FLOOR_MAJOR% (
  echo forge-py: candidate %_IP% reports Python %_VER% ^(need %FORGE_PY_FLOOR_MAJOR%.%FORGE_PY_FLOOR_MINOR%+^) 1>&2
  exit /b 1
)
if %_VMIN_CLEAN% GEQ %FORGE_PY_FLOOR_MINOR% exit /b 0
echo forge-py: candidate %_IP% reports Python %_VER% ^(need %FORGE_PY_FLOOR_MAJOR%.%FORGE_PY_FLOOR_MINOR%+^) 1>&2
exit /b 1
