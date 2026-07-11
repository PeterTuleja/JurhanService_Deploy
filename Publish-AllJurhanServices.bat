@echo off
setlocal enabledelayedexpansion

REM ==========================================================================
REM  Publish-AllJurhanServices.bat
REM
REM  Vypublikuje vsetkych 16 novych .NET 10 sluzieb do JEDNEHO priecinka
REM  (default C:\JurhanServiceNew) v strukture, ktoru ocakava
REM  Install-AllJurhanServices.ps1  (exe: <Output>\JurhanService_X.exe).
REM
REM  .pdb sa ponechavaju (cisla riadkov v stack trace v .err logoch).
REM  Jazyky DevExpress orezane na sk. Runtime: win-x64.
REM
REM  Pouzitie:
REM    Publish-AllJurhanServices.bat [vystup] [clean] [selfcontained] [only:nazov]
REM
REM  Priklady:
REM    Publish-AllJurhanServices.bat
REM    Publish-AllJurhanServices.bat clean
REM    Publish-AllJurhanServices.bat D:\Deploy clean
REM    Publish-AllJurhanServices.bat clean selfcontained
REM    Publish-AllJurhanServices.bat only:ImportObjednavok
REM ==========================================================================

set "OUTPUT=C:\JurhanServiceNew"
set "DOCLEAN="
set "SELFCONTAINED=false"
set "FILTER="

REM Koren so zdrojmi sluzieb (Deploy je podpriecinok JurhanService) zachyt PRED parseargs -
REM shift v loope posuva aj %0, takze %~dp0 by po loope uz neukazoval na tento bat.
for %%I in ("%~dp0..") do set "SERVICESROOT=%%~fI"

:parseargs
if "%~1"=="" goto argsdone
set "A=%~1"
if /i "!A!"=="clean" ( set "DOCLEAN=1" & shift & goto parseargs )
if /i "!A!"=="selfcontained" ( set "SELFCONTAINED=true" & shift & goto parseargs )
if /i "!A:~0,5!"=="only:" ( set "FILTER=!A:~5!" & shift & goto parseargs )
set "OUTPUT=!A!"
shift
goto parseargs
:argsdone

set "SERVICES=AktualizaciaBalikov AktualizaciaStatusov AktualizaciaZasob DuplicitneObjednavky ExportKurierov FakturyEmailom FakturyKaufland HodnoteniaEmailom ImportDobropisov ImportFaktur ImportObjednavok KontrolaUhrad KontrolaUhradFaktur MazanieDokladov RecenzieEmailom SparovaneKarty"

if defined DOCLEAN (
    if exist "%OUTPUT%" (
        echo Cistim %OUTPUT% ...
        rmdir /s /q "%OUTPUT%"
    )
)

set /a OK=0
set /a FAIL=0
set "FAILED="

for %%S in (%SERVICES%) do (
    set "SKIP="
    if defined FILTER ( echo %%S| find /i "!FILTER!" >nul || set "SKIP=1" )
    if not defined SKIP (
        set "CSPROJ=!SERVICESROOT!\%%S\JurhanService_%%S\JurhanService_%%S.csproj"
        echo.
        echo ==^> Publikujem JurhanService_%%S  -^>  !OUTPUT!
        if not exist "!CSPROJ!" (
            echo    CHYBA: csproj nenajdeny: !CSPROJ!
            set /a FAIL+=1
            set "FAILED=!FAILED! JurhanService_%%S"
        ) else (
            dotnet publish "!CSPROJ!" -c Release -r win-x64 --self-contained !SELFCONTAINED! -o "!OUTPUT!" -p:SatelliteResourceLanguages=sk
            if errorlevel 1 (
                echo    publish ZLYHAL: JurhanService_%%S
                set /a FAIL+=1
                set "FAILED=!FAILED! JurhanService_%%S"
            ) else (
                set /a OK+=1
            )
        )
    )
)

REM --- Uprac zbytocne subory z outputu ---------------------------------------
REM  XML dokumentacia referencii (~24 MB, hlavne DevExpress) sa za behu nikdy
REM  nenacita - je len pre IntelliSense. Lokalizacne podpriecinky (de/es/ja/...)
REM  netreba, aplikacia bezi v sk (nechavame len 'sk' a 'runtimes').
REM  Nemazeme .pdb - drzia cisla riadkov v stack trace v .err logoch.
if exist "%OUTPUT%" (
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

echo.
echo ==========================================================================
echo Hotovo: !OK! vypublikovanych, !FAIL! zlyhalo  -^>  !OUTPUT!
if /i "%SELFCONTAINED%"=="true" (
    echo Rezim: self-contained ^(runtime zbaleny, na serveri netreba .NET^)
) else (
    echo Rezim: framework-dependent ^(na serveri treba .NET 10 Desktop Runtime x64^)
)
if !FAIL! gtr 0 (
    echo ZLYHALO:!FAILED!
) else (
    echo Dalej: na serveri spusti  Install-AllJurhanServices.ps1 -RootPath "!OUTPUT!"  ^(ako spravca^)
)
echo ==========================================================================

endlocal
