@echo off
setlocal enabledelayedexpansion

REM ==========================================================================
REM  Update-AllJurhanServices.bat
REM
REM  Spusta sa NA SERVERI (ako spravca) z C:\JurhanDeploy, kde je nakopirovany
REM  aj zip balik. Nasadi novy balik sluzieb:
REM    1. rozbali JurhanServiceNew.zip (hlada sa pri tomto bate, v aktualnom
REM       priecinku a v C:\JurhanDeploy) a skontroluje jeho strukturu
REM    2. zastavi beziace sluzby JurhanServiceNew_*
REM    3. PREPISE subory zo zipu do C:\JurhanServiceNew - nic nemaze, pracovne
REM       podadresare a logy ostavaju nedotknute
REM    4. znova spusti sluzby, ktore predtym bezali
REM
REM  Wrapper nad Update-AllJurhanServices.ps1 - VSETKU logiku robi PowerShell
REM  skript vratane logovania (Update_<datum>_<cas>.log). Tento bat len prelozi
REM  argumenty a na konci pocka na klaves (aby okno po dvojkliku nezmizlo).
REM  Ked treba zmenit spravanie, meni sa .ps1, nie tento subor.
REM
REM  Registraciu sluzieb NEMENI - na prvu registraciu pouzi
REM  Install-AllJurhanServices.ps1.
REM
REM  Pouzitie:
REM    Update-AllJurhanServices.bat [cesta_k_zip] [startall]
REM
REM  Priklady:
REM    Update-AllJurhanServices.bat
REM    Update-AllJurhanServices.bat D:\Prenos\JurhanServiceNew.zip
REM    Update-AllJurhanServices.bat startall
REM ==========================================================================

REM Cestu k .ps1 zachyt PRED parseargs - shift v loope posuva aj %0, takze %~dp0
REM by po loope uz neukazoval na tento bat.
set "PS1=%~dp0Update-AllJurhanServices.ps1"

set "ZIP="
set "EXTRA="

:parseargs
if "%~1"=="" goto argsdone
set "A=%~1"
if /i "!A!"=="startall" ( set "EXTRA=!EXTRA! -StartAll" & shift & goto parseargs )
set "ZIP=!A!"
shift
goto parseargs
:argsdone

REM Zastavovanie/spustanie sluzieb vyzaduje spravcu - skontroluj hned tu,
REM nech chyba nezanikne v zavretom okne PowerShellu.
net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo CHYBA: Tento skript treba spustit AKO SPRAVCA
    echo        ^(pravy klik na .bat - Run as administrator^).
    echo.
    pause
    exit /b 1
)

set "ZIPARG="
if defined ZIP set "ZIPARG= -ZipPath "!ZIP!""

powershell -NoProfile -ExecutionPolicy Bypass -File "!PS1!"!ZIPARG!!EXTRA!
set "PSEXIT=!ERRORLEVEL!"

echo.
pause
endlocal & exit /b %PSEXIT%
