@echo off
setlocal enabledelayedexpansion

REM ==========================================================================
REM  Publish-AllJurhanProgramy.bat
REM
REM  Vypublikuje vsetky desktopove programy z podpriecinkov
REM  C:\Projekty\Private\JurhanProgramy do JEDNEHO priecinka
REM  (default C:\JurhanProgramyNew).
REM
REM  Wrapper nad Publish-AllJurhanProgramy.ps1 - discovery programov (kazdy
REM  .csproj s OutputType Exe/WinExe, kniznice sa vynechaju) aj logovanie
REM  (PublishProgramy_<datum>_<cas>.log, vystup ide sucasne na obrazovku aj
REM  do suboru) robi PowerShell skript. Novy podpriecinok s programom sa
REM  zahrnie automaticky.
REM
REM  Do logu idu len chyby + suhrn; plny vypis kompilatora: `showwarnings`.
REM  Po publishi sa z outputu upracu XML dokumentacie a cudzie lokalizacie
REM  (nechava sa 'sk' a 'runtimes') - rovnako ako Publish-AllJurhanServices.bat.
REM  .pdb sa ponechavaju (cisla riadkov v stack trace v .err logoch).
REM
REM  Pouzitie:
REM    Publish-AllJurhanProgramy.bat [vystup] [clean] [selfcontained] [only:nazov] [showwarnings]
REM
REM  Priklady:
REM    Publish-AllJurhanProgramy.bat
REM    Publish-AllJurhanProgramy.bat clean
REM    Publish-AllJurhanProgramy.bat D:\Deploy clean
REM    Publish-AllJurhanProgramy.bat only:JurhanZisk
REM    Publish-AllJurhanProgramy.bat showwarnings
REM ==========================================================================

REM Cestu k .ps1 zachyt PRED parseargs - shift v loope posuva aj %0, takze %~dp0
REM by po loope uz neukazoval na tento bat.
set "PS1=%~dp0Publish-AllJurhanProgramy.ps1"

set "OUTPUT=C:\JurhanProgramyNew"
set "DOCLEAN="
set "SELFCONTAINED="
set "FILTER="
set "SHOWWARN="

:parseargs
if "%~1"=="" goto argsdone
set "A=%~1"
if /i "!A!"=="clean" ( set "DOCLEAN=1" & shift & goto parseargs )
if /i "!A!"=="selfcontained" ( set "SELFCONTAINED=1" & shift & goto parseargs )
if /i "!A!"=="showwarnings" ( set "SHOWWARN=1" & shift & goto parseargs )
if /i "!A:~0,5!"=="only:" ( set "FILTER=!A:~5!" & shift & goto parseargs )
set "OUTPUT=!A!"
shift
goto parseargs
:argsdone

set "EXTRA="
if defined DOCLEAN set "EXTRA=!EXTRA! -Clean"
if defined SELFCONTAINED set "EXTRA=!EXTRA! -SelfContained"
if defined SHOWWARN set "EXTRA=!EXTRA! -ShowWarnings"
if defined FILTER set "EXTRA=!EXTRA! -Only !FILTER!"

powershell -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -OutputRoot "!OUTPUT!"!EXTRA!
set "PSEXIT=!ERRORLEVEL!"

REM --- Uprac zbytocne subory z outputu ---------------------------------------
REM  XML dokumentacia referencii (~24 MB, hlavne DevExpress) sa za behu nikdy
REM  nenacita - je len pre IntelliSense. Lokalizacne podpriecinky (de/es/ja/...)
REM  netreba, aplikacie bezia v sk (nechavame len 'sk' a 'runtimes').
REM  Nemazeme .pdb - drzia cisla riadkov v stack trace v .err logoch.
if !PSEXIT! equ 0 if exist "%OUTPUT%" (
    echo.
    echo Cistim zbytocne subory z outputu ^(XML dokumentacia + cudzie lokalizacie^) ...
    del /q "%OUTPUT%\*.xml" 2>nul
    for /d %%L in ("%OUTPUT%\*") do (
        if /i not "%%~nxL"=="sk" if /i not "%%~nxL"=="runtimes" (
            echo    - odstranujem lokalizaciu: %%~nxL
            rmdir /s /q "%%L"
        )
    )
)

endlocal & exit /b %PSEXIT%
