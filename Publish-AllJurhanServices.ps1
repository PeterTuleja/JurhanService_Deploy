<#
.SYNOPSIS
    Vypublikuje vsetkych 17 novych .NET 10 sluzieb do JEDNEHO priecinka (default C:\JurhanServiceNew).
    Vsetky exe (JurhanService_X.exe) aj zdielane DLL su v tom istom priecinku - zdielane kniznice
    (JurhanLib, DevExpress, Kros?) su tam len raz. Zhoduje sa s -RootPath v Install-AllJurhanServices.ps1
    (exe: <OutputRoot>\<JurhanService_X>.exe).

    Spolu so sluzbami sa do rovnakeho priecinka publikuje aj JurhanServiceRun.exe -
    WinForms spustac na manualne spustenie jednotlivych spracovani. Nie je to sluzba
    (Install-AllJurhanServices.ps1 ju neregistruje), len vyuziva uz nakopirovane
    zdielane DLL v tom istom priecinku.

    Framework-dependent (default): na serveri treba nainstalovat .NET 10 Desktop Runtime (x64).
    Self-contained (-SelfContained): runtime sa zbali do outputu, na serveri netreba nic
    (okrem Microsoft Access Database Engine 2016 x64 pre ACE.OLEDB.12.0).

    .pdb sa ZAMERNE ponechavaju - vdaka nim maju .err logy sluzieb cisla riadkov v stack trace.

.PARAMETER OutputRoot
    Jeden spolocny priecinok, kam sa publikuju vsetky sluzby (default C:\JurhanServiceNew).
    Zhoduje sa s -RootPath v Install-AllJurhanServices.ps1.

.PARAMETER Clean
    Pred publikovanim vymaze CELY $OutputRoot (cisty deploy). Pozor pri -Only: vymaze aj ostatne.

.PARAMETER Configuration
    Release (default) / Debug.

.PARAMETER Runtime
    RID (default win-x64).

.PARAMETER SelfContained
    Ak je zadane, zbali .NET runtime do outputu (netreba instalovat Desktop Runtime na server).

.PARAMETER SatelliteLanguages
    Ktore jazykove mutacie DevExpress resources ponechat (default 'sk' - app bezi pod sk-SK).
    'all' = ponechat vsetky.

.PARAMETER Only
    Vypublikuje len projekty, ktorych nazov obsahuje tento retazec (na testovanie jedneho).
    Filtruje aj spustac - napr. -Only JurhanServiceRun vypublikuje len jeho.

.PARAMETER SkipTests
    Preskoci spustenie unit testov. Bez neho sa testy spustaju vzdy a prvy padnuty
    test zastavi cely publish (do $OutputRoot sa nic nenakopiruje). Pouzivaj len
    vynimocne - napr. hotfix, ked je test rozbity z ineho dovodu nez chyba
    v nasadzovanom kode.

.PARAMETER ZipRoot
    Priecinok, do ktoreho sa na konci zabali vypublikovany output (default
    C:\JurhanDeploy). Nazov archivu sa odvodi z nazvu vystupneho priecinka:
    C:\JurhanServiceNew -> C:\JurhanDeploy\JurhanServiceNew.zip.

.PARAMETER SkipZip
    Preskoci zabalenie outputu do zip. Publish aj upratanie outputu prebehnu.

.PARAMETER ShowWarnings
    Ak je zadane, do logu ide plny vystup kompilatora vratane warningov. Bez neho sa loguju
    len chyby + suhrnne pocty (warningy zdielanych kniznic - napr. ~1400 nullable warningov
    OmegaLib pri jej rekompilacii - by inak zaplavili cely log).

.EXAMPLE
    .\Publish-AllJurhanServices.ps1

.EXAMPLE
    .\Publish-AllJurhanServices.ps1 -SelfContained -Clean

.EXAMPLE
    .\Publish-AllJurhanServices.ps1 -Only ImportObjednavok
#>
[CmdletBinding()]
param(
    [string]$OutputRoot = 'C:\JurhanServiceNew',
    [string]$Configuration = 'Release',
    [string]$Runtime = 'win-x64',
    [switch]$SelfContained,
    [string]$SatelliteLanguages = 'sk',
    [switch]$Clean,
    [string]$Only,
    [switch]$ShowWarnings,
    [switch]$SkipTests,
    [string]$ZipRoot = 'C:\JurhanDeploy',
    [switch]$SkipZip
)

$ErrorActionPreference = 'Stop'

# Cely priebeh publikovania (vratane vystupu `dotnet publish` a chyb buildu) sa loguje do
# suboru - netreba kopirovat text z okna, staci podhodit subor na analyzu.
$logPath = Join-Path $PSScriptRoot ("Publish_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {

# Zdroje sluzieb su o uroven vyssie (Deploy je podpriecinok JurhanService).
$ServicesRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Projektove (exe) nazvy - MUSIA sa zhodovat s $ExeBaseNames v Install-AllJurhanServices.ps1.
$ServiceProjects = @(
    'JurhanService_AktualizaciaBalikov'
    'JurhanService_AktualizaciaStatusov'
    'JurhanService_AktualizaciaZasob'
    'JurhanService_DuplicitneObjednavky'
    'JurhanService_ExportKurierov'
    'JurhanService_FakturyEmailom'
    'JurhanService_FakturyKaufland'
    'JurhanService_HodnoteniaEmailom'
    'JurhanService_ImportDobropisov'
    'JurhanService_ImportFaktur'
    'JurhanService_ImportObjednavok'
    'JurhanService_KontrolaUhrad'
    'JurhanService_KontrolaUhradFaktur'
    'JurhanService_MazanieDokladov'
    'JurhanService_RecenzieEmailom'
    'JurhanService_RozuctovanieDopravcov'
    'JurhanService_SparovaneKarty'
)

# JurhanServiceRun - GUI spustac spracovani. Nie je to sluzba (nepatri do $ExeBaseNames
# v Install-AllJurhanServices.ps1), publikuje sa ale do rovnakeho priecinka ako sluzby.
$RunnerProject  = 'JurhanServiceRun'
$publishRunner  = $true

if ($Only) {
    $ServiceProjects = @($ServiceProjects | Where-Object { $_ -like "*$Only*" })
    $publishRunner   = $RunnerProject -like "*$Only*"
    if (-not $ServiceProjects -and -not $publishRunner) { throw "Ziadny projekt nezodpoveda -Only '$Only'." }
}

$selfContainedFlag = if ($SelfContained) { 'true' } else { 'false' }
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# --- Predkompilacia zdielanych kniznic ----------------------------------------
# JurhanModels a JurhanLib pouzivaju vsetky sluzby - skompiluju sa najprv samostatne,
# aby sa pripadna chyba v zdielanej kniznici odhalila hned na zaciatku (a len raz),
# nie az uprostred publishu niektorej sluzby. Poradie: Models pred Lib (Lib na ne
# odkazuje). Pri chybe sa cely publish zastavi.
$SharedLibProjects = @(
    'C:\Projekty\Private\JurhanProgramy\JurhanModels\JurhanModels\JurhanModels.csproj'
    'C:\Projekty\Private\JurhanProgramy\JurhanLib\JurhanLib\JurhanLib.csproj'
)
foreach ($lib in $SharedLibProjects) {
    $libName = [System.IO.Path]::GetFileNameWithoutExtension($lib)
    if (-not (Test-Path -LiteralPath $lib)) { throw "Zdielana kniznica nenajdena: $lib" }
    Write-Host ""
    Write-Host "==> Kompilujem zdielanu kniznicu $libName" -ForegroundColor Cyan
    $buildArgs = @('build', $lib, '-c', $Configuration)
    if (-not $ShowWarnings) { $buildArgs += '-clp:ErrorsOnly;Summary' }
    & dotnet @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Kompilacia zdielanej kniznice $libName zlyhala (kod $LASTEXITCODE) - sluzby sa nepublikuju."
    }
    Write-Host "    OK: $libName" -ForegroundColor Green
}

# --- Unit testy ---------------------------------------------------------------
# Testy bezia PRED publikovanim a PRED -Clean: ked test padne, $OutputRoot ostane
# nedotknuty a nic sa don nenakopiruje.
# Hlada sa v zdrojoch sluzieb A v adresaroch zdielanych kniznic - sluzby na JurhanLib
# a JurhanModels stoja, takze ich testy musia zbehnut aj tu. Cesty sa odvodzuju
# z $SharedLibProjects, aby nevznikol druhy zoznam ciest, ktory by sa rozisiel s prvym.
# -Only testy NEfiltruje: beh testov je zlomok sekundy, draha je kompilacia, a
# zdielana JurhanLib zasahuje do vsetkych sluzieb.
$testsRun = 0
if ($SkipTests) {
    Write-Host ""
    Write-Host "Unit testy PRESKOCENE (-SkipTests)." -ForegroundColor DarkYellow
}
else {
    # Koren repozitara zdielanej kniznice: ...\JurhanLib\JurhanLib\JurhanLib.csproj -> ...\JurhanLib
    $sharedLibRoots  = @($SharedLibProjects | ForEach-Object { Split-Path -Parent (Split-Path -Parent $_) })
    $testSearchRoots = @(@($ServicesRoot) + $sharedLibRoots | Select-Object -Unique)

    $testProjects = @(Get-ChildItem -Path $testSearchRoots -Recurse -Filter '*.Tests.csproj' -File -ErrorAction SilentlyContinue |
                      Where-Object { $_.FullName -notmatch '[\\/](obj|bin|\.claude)[\\/]' } |
                      Sort-Object FullName -Unique |
                      Sort-Object Name)

    if (-not $testProjects) {
        Write-Host ""
        Write-Host "Nenasiel sa ziadny *.Tests.csproj - testy sa nespustaju." -ForegroundColor DarkYellow
    }
    else {
        Write-Host ""
        Write-Host "Spustam unit testy ($($testProjects.Count) projektov):" -ForegroundColor Cyan
        foreach ($testProject in $testProjects) {
            Write-Host ""
            Write-Host "==> Testy $($testProject.BaseName)" -ForegroundColor Cyan

            $testArgs = @('test', $testProject.FullName, '-c', $Configuration, '--nologo')
            # Vysledok testov ide z VSTest, nie z MSBuild loggera - riadok "Passed! - Failed: 0..."
            # sa zobrazi aj s ErrorsOnly. Potlacia sa len warningy kompilacie.
            if (-not $ShowWarnings) { $testArgs += '-clp:ErrorsOnly;Summary' }

            & dotnet @testArgs
            if ($LASTEXITCODE -ne 0) {
                throw "Testy $($testProject.BaseName) zlyhali (kod $LASTEXITCODE) - sluzby sa nepublikuju."
            }
            Write-Host "    OK: $($testProject.BaseName)" -ForegroundColor Green
        }
        $testsRun = $testProjects.Count
    }
}

# Vsetky sluzby idu do JEDNEHO priecinka ($OutputRoot). Zdielane DLL (JurhanLib, OmegaLib,
# DevExpress, Kros?) su tam ulozene raz; kazda sluzba ma vlastny <Name>.exe + <Name>.deps.json
# + <Name>.runtimeconfig.json, ktore sa nekonfliktuju. Zdielane DLL sa prepisu rovnakou verziou.
if ($Clean -and (Test-Path -LiteralPath $OutputRoot)) {
    Write-Host "Cistim $OutputRoot ..." -ForegroundColor DarkYellow
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}

# List + .Add() - aby sa vystup `dotnet publish` (stdout) NEzbieral do vysledkov.
$results = [System.Collections.Generic.List[object]]::new()

foreach ($proj in $ServiceProjects) {
    # Najdi .csproj (mimo obj/bin/.claude), aby sme neboli zavisli na presnom vnoreni priecinkov.
    # .claude MUSI byt vylucene: v .claude\worktrees\ ostavaju kopie projektu po starych
    # sessionach a Select-Object -First 1 by siahol po nich (radia sa pred realny priecinok).
    # V takej kopii nerezoluju relativne ProjectReference cesty - publish spadne na
    # "type or namespace JurhanLib could not be found", hoci zdroje su v poriadku.
    $csproj = Get-ChildItem -Path $ServicesRoot -Recurse -Filter "$proj.csproj" -File -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '[\\/](obj|bin|\.claude)[\\/]' } |
              Select-Object -First 1

    if (-not $csproj) {
        Write-Warning "csproj nenajdeny: $proj - preskakujem."
        $results.Add([pscustomobject]@{ Name = $proj; Ok = $false; Output = $null; Error = 'csproj nenajdeny' })
        continue
    }

    Write-Host ""
    Write-Host "==> Publikujem $proj -> $OutputRoot" -ForegroundColor Cyan

    $publishArgs = @(
        'publish', $csproj.FullName,
        '-c', $Configuration,
        '-r', $Runtime,
        '--self-contained', $selfContainedFlag,
        '-o', $OutputRoot
    )
    if ($SatelliteLanguages -and $SatelliteLanguages -ne 'all') {
        $publishArgs += "-p:SatelliteResourceLanguages=$SatelliteLanguages"
    }
    if (-not $ShowWarnings) {
        # Do logu len chyby + suhrn (pocty warningov/chyb). Warningy sa zobrazuju len pri
        # rekompilacii kniznice, takze ich pocet v logu kolise a masku ju skutocne chyby.
        $publishArgs += '-clp:ErrorsOnly;Summary'
    }

    & dotnet @publishArgs
    $ok = ($LASTEXITCODE -eq 0)
    if ($ok) {
        Write-Host "    OK: $proj" -ForegroundColor Green
    }
    else {
        Write-Host "    ZLYHALO: $proj (kod $LASTEXITCODE)" -ForegroundColor Red
    }

    $errText = if ($ok) { $null } else { "exit $LASTEXITCODE" }
    $results.Add([pscustomobject]@{ Name = $proj; Ok = $ok; Output = $OutputRoot; Error = $errText })
}

# --- Spustac JurhanServiceRun -------------------------------------------------
# JurhanServiceRun je WinForms program na manualne spustenie jednotlivych spracovani.
# Nie je to sluzba (Install-AllJurhanServices.ps1 ju neregistruje), ale publikuje sa
# do toho isteho priecinka ($OutputRoot) - vyuzije uz nakopirovane zdielane DLL
# (JurhanLib, OmegaLib, DevExpress, Kros...) a je po ruke priamo pri sluzbach.
if ($publishRunner) {
    $runnerCsproj = Join-Path $ServicesRoot 'JurhanServiceRun\JurhanServiceRun\JurhanServiceRun.csproj'

    Write-Host ""
    Write-Host "==> Publikujem spustac $RunnerProject -> $OutputRoot" -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $runnerCsproj)) {
        Write-Host "    CHYBA: csproj nenajdeny: $runnerCsproj" -ForegroundColor Red
        $results.Add([pscustomobject]@{ Name = $RunnerProject; Ok = $false; Output = $null; Error = 'csproj nenajdeny' })
    }
    else {
        $publishArgs = @(
            'publish', $runnerCsproj,
            '-c', $Configuration,
            '-r', $Runtime,
            '--self-contained', $selfContainedFlag,
            '-o', $OutputRoot
        )
        if ($SatelliteLanguages -and $SatelliteLanguages -ne 'all') {
            $publishArgs += "-p:SatelliteResourceLanguages=$SatelliteLanguages"
        }
        if (-not $ShowWarnings) { $publishArgs += '-clp:ErrorsOnly;Summary' }

        & dotnet @publishArgs
        $ok = ($LASTEXITCODE -eq 0)
        if ($ok) {
            Write-Host "    OK: $RunnerProject" -ForegroundColor Green
        }
        else {
            Write-Host "    ZLYHALO: $RunnerProject (kod $LASTEXITCODE)" -ForegroundColor Red
        }

        $errText = if ($ok) { $null } else { "exit $LASTEXITCODE" }
        $results.Add([pscustomobject]@{ Name = $RunnerProject; Ok = $ok; Output = $OutputRoot; Error = $errText })
    }
}

$sw.Stop()
# --- Uprac zbytocne subory z outputu ------------------------------------------
# XML dokumentacia referencii (~24 MB, hlavne DevExpress) sa za behu nikdy nenacita -
# je len pre IntelliSense. Lokalizacne podpriecinky (de/es/ja/...) netreba, sluzby
# bezia v sk (nechavame len 'sk' a 'runtimes'). .pdb sa NEmazu - drzia cisla riadkov
# v stack trace v .err logoch sluzieb.
# Bolo to v .bat wrapperi; presunute sem, aby sa upratalo aj pri priamom spusteni
# tohto skriptu a hlavne aby zip nizsie nezabalil to, co sa ma zahodit.
if (Test-Path -LiteralPath $OutputRoot) {
    Write-Host ""
    Write-Host "Cistim zbytocne subory z outputu (XML dokumentacia + cudzie lokalizacie) ..." -ForegroundColor DarkYellow
    Get-ChildItem -LiteralPath $OutputRoot -Filter '*.xml' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $OutputRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('sk', 'runtimes') } |
        ForEach-Object {
            Write-Host "   - odstranujem lokalizaciu: $($_.Name)"
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
}

# --- Zabalenie outputu do zip -------------------------------------------------
# Bali sa AZ PO upratani, aby v archive nebolo to, co sa vyssie zmazalo.
# Archiv obsahuje aj korenovy priecinok (JurhanServiceNew\...), takze rozbalenim
# na serveri do C:\ vznikne presne cesta, ktoru ocakava Install-AllJurhanServices.ps1.
# Ked publish neprebehol cely, NEbali sa: polovicny balik vyzera zvonku ako hotovy.
$zipPath = $null
$zipInfo = 'nezabalene'
if ($SkipZip) {
    $zipInfo = 'PRESKOCENE (-SkipZip)'
}
elseif (@($results | Where-Object { -not $_.Ok }).Count -gt 0) {
    $zipInfo = 'preskocene - publish neprebehol cely'
}
elseif (-not (Test-Path -LiteralPath $OutputRoot)) {
    $zipInfo = "preskocene - $OutputRoot neexistuje"
}
else {
    $zipPath = Join-Path $ZipRoot ((Split-Path -Leaf $OutputRoot) + '.zip')
    Write-Host ""
    Write-Host "Balim $OutputRoot -> $zipPath ..." -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $ZipRoot)) {
        New-Item -ItemType Directory -Path $ZipRoot -Force | Out-Null
    }
    # CreateFromDirectory na uz existujuci subor spadne, stary archiv sa preto zmaze
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

    # Compress-Archive je na priecinok tejto velkosti (stovky MB, tisice suborov)
    # radovo pomalsi, preto ZipFile priamo z .NET
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $OutputRoot, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)

    $zipInfo = "$zipPath ($([math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)) MB)"
    Write-Host "    OK: $zipInfo" -ForegroundColor Green
}

# @() je nutne: .bat wrapper spusta tento skript cez Windows PowerShell 5.1 a tam
# .Count nad JEDNYM pscustomobject vrati prazdno (v PowerShelli 7 vrati 1). Pri
# publikovani jedinej sluzby (-Only) sa to prejavilo ako "Hotovo: /1 projektov".
$okCount = @($results | Where-Object Ok).Count
Write-Host ""
Write-Host "Hotovo: $okCount/$($results.Count) projektov (sluzby + spustac) vypublikovanych za $([int]$sw.Elapsed.TotalSeconds)s do $OutputRoot." -ForegroundColor Cyan
if ($SkipTests) {
    Write-Host "Unit testy: PRESKOCENE (-SkipTests)." -ForegroundColor DarkYellow
}
else {
    Write-Host "Unit testy: $testsRun projektov preslo."
}
$mode = if ($SelfContained) { 'self-contained (runtime zbaleny)' } else { 'framework-dependent (treba .NET 10 Desktop Runtime x64 na serveri)' }
Write-Host "Rezim: $mode"
Write-Host "Zip: $zipInfo"
$failed = $results | Where-Object { -not $_.Ok }
if ($failed) {
    Write-Host "ZLYHALO:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $($_.Name): $($_.Error)" -ForegroundColor Red }
}
else {
    Write-Host "Dalej: spusti Install-AllJurhanServices.ps1 -RootPath '$OutputRoot' (ako spravca) na registraciu sluzieb." -ForegroundColor Green
}

}
finally {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host "LOG ULOZENY DO SUBORU: $logPath" -ForegroundColor Yellow
    Write-Host "Tento subor podhod (netreba kopirovat text z okna)." -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch { }
}
