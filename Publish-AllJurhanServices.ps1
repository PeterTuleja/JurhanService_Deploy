<#
.SYNOPSIS
    Vypublikuje vsetkych 17 novych .NET 10 sluzieb do JEDNEHO priecinka (default C:\JurhanServiceNew).
    Vsetky exe (JurhanService_X.exe) aj zdielane DLL su v tom istom priecinku - zdielane kniznice
    (JurhanLib, DevExpress, Kros?) su tam len raz. Zhoduje sa s -RootPath v Install-AllJurhanServices.ps1
    (exe: <OutputRoot>\<JurhanService_X>.exe).

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
    Vypublikuje len sluzby, ktorych nazov obsahuje tento retazec (na testovanie jednej).

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
    [string]$Only
)

$ErrorActionPreference = 'Stop'

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

if ($Only) {
    $ServiceProjects = $ServiceProjects | Where-Object { $_ -like "*$Only*" }
    if (-not $ServiceProjects) { throw "Ziadna sluzba nezodpoveda -Only '$Only'." }
}

$selfContainedFlag = if ($SelfContained) { 'true' } else { 'false' }
$sw = [System.Diagnostics.Stopwatch]::StartNew()

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
    # Najdi .csproj (mimo obj/bin), aby sme neboli zavisli na presnom vnoreni priecinkov.
    $csproj = Get-ChildItem -Path $ServicesRoot -Recurse -Filter "$proj.csproj" -File -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } |
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

    & dotnet @publishArgs
    $ok = ($LASTEXITCODE -eq 0)
    if (-not $ok) { Write-Warning "publish ZLYHAL: $proj (kod $LASTEXITCODE)" }

    $errText = if ($ok) { $null } else { "exit $LASTEXITCODE" }
    $results.Add([pscustomobject]@{ Name = $proj; Ok = $ok; Output = $OutputRoot; Error = $errText })
}

$sw.Stop()
$okCount = ($results | Where-Object Ok).Count
Write-Host ""
Write-Host "Hotovo: $okCount/$($results.Count) sluzieb vypublikovanych za $([int]$sw.Elapsed.TotalSeconds)s do $OutputRoot." -ForegroundColor Cyan
$mode = if ($SelfContained) { 'self-contained (runtime zbaleny)' } else { 'framework-dependent (treba .NET 10 Desktop Runtime x64 na serveri)' }
Write-Host "Rezim: $mode"
$failed = $results | Where-Object { -not $_.Ok }
if ($failed) {
    Write-Host "ZLYHALO:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $($_.Name): $($_.Error)" -ForegroundColor Red }
}
else {
    Write-Host "Dalej: spusti Install-AllJurhanServices.ps1 -RootPath '$OutputRoot' (ako spravca) na registraciu sluzieb." -ForegroundColor Green
}
