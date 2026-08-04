@echo off
setlocal enabledelayedexpansion

REM ==========================================================================
REM  Install-RozuctovanieDopravcov.bat
REM
REM  Zaregistruje sluzbu RozuctovanieDopravcov ako Windows Service.
REM  Wrapper nad Install-JurhanService.ps1:
REM    SCM nazov: JurhanServiceNew_RozuctovanieDopravcov  (musi sediet s
REM               Program.serviceName v projekte - prefix "New" kvoli
REM               koexistencii so starymi net48 sluzbami JurhanService_*)
REM    Exe:       <RootPath>\JurhanService_RozuctovanieDopravcov.exe
REM               (default RootPath C:\JurhanServiceNew - spolocny priecinok
REM               z Publish-AllJurhanServices)
REM
REM  SPUSTIT AKO SPRAVCA. Konto (Log On As) sa vypyta interaktivne,
REM  alebo pouzi parameter `localsystem` na rychly lokalny test.
REM
REM  Pouzitie:
REM    Install-RozuctovanieDopravcov.bat [rootpath] [localsystem]
REM
REM  Priklady:
REM    Install-RozuctovanieDopravcov.bat
REM    Install-RozuctovanieDopravcov.bat localsystem
REM    Install-RozuctovanieDopravcov.bat D:\JurhanServiceNew
REM ==========================================================================

REM Cestu k .ps1 zachyt PRED parseargs - shift v loope posuva aj %0, takze %~dp0
REM by po loope uz neukazoval na tento bat.
set "PS1=%~dp0Install-JurhanService.ps1"

REM Registracia sluzby (sc.exe create) vyzaduje admina - over hned na zaciatku.
net session >nul 2>&1
if errorlevel 1 (
    echo CHYBA: Tento skript treba spustit ako spravca ^(Run as administrator^).
    exit /b 1
)

set "ROOTPATH=C:\JurhanServiceNew"
set "LOCALSYSTEM="

:parseargs
if "%~1"=="" goto argsdone
set "A=%~1"
if /i "!A!"=="localsystem" ( set "LOCALSYSTEM=1" & shift & goto parseargs )
set "ROOTPATH=!A!"
shift
goto parseargs
:argsdone

set "EXE=!ROOTPATH!\JurhanService_RozuctovanieDopravcov.exe"
if not exist "!EXE!" (
    echo CHYBA: exe nenajdene: !EXE!
    echo Najprv vypublikuj sluzby: Publish-AllJurhanServices.bat ^(alebo .ps1^).
    exit /b 1
)

set "EXTRA="
if defined LOCALSYSTEM set "EXTRA= -LocalSystem"

powershell -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -Name JurhanServiceNew_RozuctovanieDopravcov -ExePath "!EXE!" -Description "Rozuctovanie plateb dopravcov z IMAP schranky platby@jurhan.com"!EXTRA!
set "PSEXIT=!ERRORLEVEL!"

endlocal & exit /b %PSEXIT%
