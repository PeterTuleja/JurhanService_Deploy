@echo off
setlocal enabledelayedexpansion

REM ==========================================================================
REM  Publish-AllJurhanServices.bat
REM
REM  Vypublikuje vsetkych 17 .NET 10 sluzieb do JEDNEHO priecinka
REM  (default C:\JurhanServiceNew) v strukture, ktoru ocakava
REM  Install-AllJurhanServices.ps1  (exe: <Output>\JurhanService_X.exe).
REM  Spolu s nimi sa publikuje aj JurhanServiceRun.exe - WinForms spustac
REM  na manualne spustenie spracovani (nie je to sluzba, neregistruje sa).
REM
REM  Wrapper nad Publish-AllJurhanServices.ps1 - VSETKO robi PowerShell skript:
REM  zoznam sluzieb, predkompilacia zdielanych kniznic (JurhanModels, JurhanLib),
REM  unit testy, publish, upratanie outputu, zabalenie do zip aj logovanie
REM  (Publish_<datum>_<cas>.log). Tento bat len prelozi argumenty.
REM
REM  POZOR: tento subor BYVAL samostatnou kopiou publish logiky. Rozisiel sa
REM  s .ps1 (chybala mu predkompilacia zdielanych kniznic aj unit testy) a
REM  zoznam sluzieb sa musel drzat zosuladeny na troch miestach. Preto je
REM  teraz wrapper - rovnako ako Publish-AllJurhanProgramy.bat. Ked treba
REM  zmenit spravanie publishu, meni sa .ps1, nie tento subor.
REM
REM  Unit testy bezia PRED publikovanim: prvy padnuty test zastavi cely publish
REM  a do outputu sa nic nenakopiruje. Preskocit sa daju cez `skiptests`.
REM
REM  Do logu idu len chyby + suhrn; plny vypis kompilatora: `showwarnings`.
REM  Po publishi sa z outputu upracu XML dokumentacie a cudzie lokalizacie
REM  (nechava sa 'sk' a 'runtimes'); .pdb sa ponechavaju (cisla riadkov v stack
REM  trace v .err logoch). Potom sa cely output zabali do
REM  C:\JurhanDeploy\JurhanServiceNew.zip - vratane korenoveho priecinka, takze
REM  rozbalenim na serveri do C:\ vznikne rovno C:\JurhanServiceNew.
REM  Zabalenie sa da vypnut cez `skipzip`.
REM
REM  Pouzitie:
REM    Publish-AllJurhanServices.bat [vystup] [clean] [selfcontained] [only:nazov] [showwarnings] [skiptests] [skipzip]
REM
REM  Priklady:
REM    Publish-AllJurhanServices.bat
REM    Publish-AllJurhanServices.bat clean
REM    Publish-AllJurhanServices.bat D:\Deploy clean
REM    Publish-AllJurhanServices.bat clean selfcontained
REM    Publish-AllJurhanServices.bat only:ImportObjednavok
REM    Publish-AllJurhanServices.bat only:JurhanServiceRun
REM    Publish-AllJurhanServices.bat showwarnings
REM ==========================================================================

REM Cestu k .ps1 zachyt PRED parseargs - shift v loope posuva aj %0, takze %~dp0
REM by po loope uz neukazoval na tento bat.
set "PS1=%~dp0Publish-AllJurhanServices.ps1"

set "OUTPUT=C:\JurhanServiceNew"
set "DOCLEAN="
set "SELFCONTAINED="
set "FILTER="
set "SHOWWARN="
set "SKIPTESTS="
set "SKIPZIP="

:parseargs
if "%~1"=="" goto argsdone
set "A=%~1"
if /i "!A!"=="clean" ( set "DOCLEAN=1" & shift & goto parseargs )
if /i "!A!"=="selfcontained" ( set "SELFCONTAINED=1" & shift & goto parseargs )
if /i "!A!"=="showwarnings" ( set "SHOWWARN=1" & shift & goto parseargs )
if /i "!A!"=="skiptests" ( set "SKIPTESTS=1" & shift & goto parseargs )
if /i "!A!"=="skipzip" ( set "SKIPZIP=1" & shift & goto parseargs )
if /i "!A:~0,5!"=="only:" ( set "FILTER=!A:~5!" & shift & goto parseargs )
set "OUTPUT=!A!"
shift
goto parseargs
:argsdone

set "EXTRA="
if defined DOCLEAN set "EXTRA=!EXTRA! -Clean"
if defined SELFCONTAINED set "EXTRA=!EXTRA! -SelfContained"
if defined SHOWWARN set "EXTRA=!EXTRA! -ShowWarnings"
if defined SKIPTESTS set "EXTRA=!EXTRA! -SkipTests"
if defined SKIPZIP set "EXTRA=!EXTRA! -SkipZip"
if defined FILTER set "EXTRA=!EXTRA! -Only !FILTER!"

powershell -NoProfile -ExecutionPolicy Bypass -File "!PS1!" -OutputRoot "!OUTPUT!"!EXTRA!
set "PSEXIT=!ERRORLEVEL!"

endlocal & exit /b %PSEXIT%
