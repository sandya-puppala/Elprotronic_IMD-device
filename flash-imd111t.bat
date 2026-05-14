@echo off
REM ==========================================================================
REM  flash-imd111t.bat - drive the Generic-FPA CLI to program an IMD111T-6F040
REM  via the v1.04 iMOTION API DLL (bypasses the broken v3.02 unified GUI).
REM
REM  PREREQUISITE: the server must already be running in another window:
REM     cd "C:\Elprotronic\Generic-FPA-DLLs (x64)\bin\x64"
REM     Generic-CommandLine-Server.exe FPAs-setup.ini -b
REM
REM  USAGE:
REM     flash-imd111t.bat classb-en   - program Class-B-ENABLED params (the
REM                                     file the v3.02 GUI fails on)
REM     flash-imd111t.bat working     - mass-erase + program Working params
REM                                     (Class-B disabled) - recovers comms
REM     flash-imd111t.bat recover     - mass-erase + firmware + Working params
REM                                     (full recovery of a bricked chip)
REM     flash-imd111t.bat "<full path to any .ldf>"  - program that file as-is
REM ==========================================================================
setlocal

REM 32-bit bundle: the only Generic-FPA build that can load the x86-only
REM iMOTION v1.05 DLL. Its FlashProiMOTION-FPA1.dll was swapped to v1.0.5.0
REM (v1.04 original kept as FlashProiMOTION-FPA1.dll.v1.0.4.0.bak).
set BIN=C:\Elprotronic\Generic-FPA-DLLs (x86)\bin\Win32
REM imd111t-cli.cfg is MCE11.CFG with PromptForPowerCycle=0 and
REM PromptForFirstPageErase_coreM0only=0 so AutoProgram power-cycles the
REM target itself in headless mode (no dialog for the server to block on).
set CFG=C:\Elprotronic\imd111t-cli.cfg
set LDFDIR=C:\Elprotronic\imd111t-ldf
set CLIENT=CommandLine-Client.exe

set MASSERASE=0
set FW=
set LDF=

if /i "%~1"=="classb-en" (
    set LDF=%LDFDIR%\Not_Working_ClassB_enabled_I2Cdisable.ldf
) else if /i "%~1"=="working" (
    set MASSERASE=1
    set LDF=%LDFDIR%\Working_ClassB_disabled_I2Cdisable.ldf
) else if /i "%~1"=="recover" (
    set MASSERASE=1
    set FW=%LDFDIR%\firmware_V5.03.00.ldf
    set LDF=%LDFDIR%\Working_ClassB_disabled_I2Cdisable.ldf
) else if not "%~1"=="" (
    set LDF=%~1
) else (
    echo ERROR: no target specified.
    echo.
    echo Usage:
    echo    flash-imd111t.bat classb-en   - program Class-B-enabled params
    echo    flash-imd111t.bat working     - mass-erase + Working params
    echo    flash-imd111t.bat recover     - mass-erase + firmware + Working params
    echo    flash-imd111t.bat "C:\path\to\file.ldf"
    exit /b 1
)

cd /d "%BIN%"

echo ==========================================================================
echo  CFG : %CFG%
if not "%FW%"=="" echo  FW  : %FW%
echo  LDF : %LDF%
echo  Mass-erase first: %MASSERASE%
echo ==========================================================================
echo.

echo --- ConfigFileLoad -------------------------------------------------------
"%CLIENT%" -i 1 -m ConfigFileLoad "%CFG%"
echo.

if "%MASSERASE%"=="1" (
    echo --- Memory_Erase ---------------------------------------------------------
    "%CLIENT%" -i 1 -m Memory_Erase 0
    echo.
)

if not "%FW%"=="" (
    echo --- ReadCodeFile [firmware] ----------------------------------------------
    "%CLIENT%" -i 1 -m ReadCodeFile "%FW%"
    echo.
    echo --- AutoProgram [firmware] -----------------------------------------------
    "%CLIENT%" -i 1 -m AutoProgram 0
    echo.
)

echo --- ReadCodeFile [parameters] --------------------------------------------
"%CLIENT%" -i 1 -m ReadCodeFile "%LDF%"
echo.

echo --- AutoProgram [parameters] ---------------------------------------------
"%CLIENT%" -i 1 -m AutoProgram 0
echo.

echo --- Report_Message -------------------------------------------------------
"%CLIENT%" -i 1 -m Report_Message
echo.

echo ==========================================================================
echo  Done. Read the RETURN: codes above - RETURN: 1 means that step passed.
echo  Any other RETURN code on ConfigFileLoad / ReadCodeFile / AutoProgram is
echo  a failure - copy the whole output back for diagnosis.
echo ==========================================================================
endlocal
pause
