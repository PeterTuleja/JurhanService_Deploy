<#
.SYNOPSIS
    Vypublikuje vsetky desktopove programy z podpriecinkov C:\Projekty\Private\JurhanProgramy
    do JEDNEHO spolocneho priecinka (default C:\JurhanProgramyNew) - rovnaky princip ako
    Publish-AllJurhanServices.ps1 (zdielane DLL su v priecinku len raz).

    Programy sa NEVYMENOVAVAJU natvrdo - skript automaticky prehlada vsetky podpriecinky
    a vezme kazdy .csproj s OutputType Exe/WinExe. Ked pribudne novy podpriecinok s
    programom, zahrnie sa sam od seba. Kniznice (JurhanLib, JurhanModels, JurhanGraphQL...)
    maju OutputType Library, takze sa automaticky vynechaju. Preskakuju sa aj obj/bin,
    .claude (worktrees) a *.Tests projekty.

    Do logu idu len chyby + suhrn (pocty warningov/chyb) - warningy zdielanych kniznic
    by inak zaplavili cely log. Plny vypis kompilatora: -ShowWarnings.

    .pdb sa ZAMERNE ponechavaju - vdaka nim maju .err logy cisla riadkov v stack trace.

.PARAMETER OutputRoot
    Jeden spolocny priecinok, kam sa publikuju vsetky programy (default C:\JurhanProgramyNew).

.PARAMETER ProgramyRoot
    Koren so zdrojmi programov (default C:\Projekty\Private\JurhanProgramy).

.PARAMETER Clean
    Pred publikovanim vymaze CELY $OutputRoot (cisty deploy). Pozor pri -Only: vymaze aj ostatne.

.PARAMETER Configuration
    Release (default) / Debug.

.PARAMETER Runtime
    RID (default win-x64).

.PARAMETER SelfContained
    Ak je zadane, zbali .NET runtime do outputu (netreba instalovat Desktop Runtime).

.PARAMETER SatelliteLanguages
    Ktore jazykove mutacie DevExpress resources ponechat (default 'sk'). 'all' = vsetky.

.PARAMETER Only
    Vypublikuje len programy, ktorych nazov projektu alebo podpriecinka obsahuje tento
    retazec (na testovanie jedneho).

.PARAMETER ShowWarnings
    Ak je zadane, do logu ide plny vystup kompilatora vratane warningov.

.EXAMPLE
    .\Publish-AllJurhanProgramy.ps1

.EXAMPLE
    .\Publish-AllJurhanProgramy.ps1 -Only JurhanZisk

.EXAMPLE
    .\Publish-AllJurhanProgramy.ps1 -SelfContained -Clean
#>
[CmdletBinding()]
param(
    [string]$OutputRoot = 'C:\JurhanProgramyNew',
    [string]$ProgramyRoot = 'C:\Projekty\Private\JurhanProgramy',
    [string]$Configuration = 'Release',
    [string]$Runtime = 'win-x64',
    [switch]$SelfContained,
    [string]$SatelliteLanguages = 'sk',
    [switch]$Clean,
    [string]$Only,
    [switch]$ShowWarnings
)

$ErrorActionPreference = 'Stop'

# Cely priebeh publikovania (vratane vystupu `dotnet publish` a chyb buildu) sa loguje do
# suboru - netreba kopirovat text z okna, staci podhodit subor na analyzu.
$logPath = Join-Path $PSScriptRoot ("PublishProgramy_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {

if (-not (Test-Path -LiteralPath $ProgramyRoot)) { throw "ProgramyRoot neexistuje: $ProgramyRoot" }

# --- Auto-discovery programov -------------------------------------------------
# Kazdy .csproj mimo obj/bin/.claude, ktory ma OutputType Exe alebo WinExe.
# (Kniznice OutputType nemaju alebo maju Library - tie sa nenasadzuju, su to len
# DLL vyuzivane v programoch a servisoch.)
$allCsproj = Get-ChildItem -Path $ProgramyRoot -Recurse -Filter '*.csproj' -File -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch '[\\/](obj|bin|\.claude)[\\/]' -and
                            $_.Name -notlike '*.Tests.csproj' }

$programs = foreach ($csproj in $allCsproj) {
    try { $xml = [xml](Get-Content -LiteralPath $csproj.FullName -Raw) } catch { continue }
    $outputType = @($xml.Project.PropertyGroup.OutputType) | Where-Object { $_ } | Select-Object -First 1
    if ("$outputType".Trim() -match '^(Win)?Exe$') {
        # Nazov podpriecinka priamo pod $ProgramyRoot (kvoli -Only a prehladu; nazov
        # projektu sa nemusi zhodovat s podpriecinkom, napr. ExportKurierovNew -> ExportKurierov).
        $relative  = $csproj.FullName.Substring($ProgramyRoot.TrimEnd('\').Length + 1)
        $topFolder = $relative.Split('\')[0]
        [pscustomobject]@{ Name = $csproj.BaseName; Folder = $topFolder; Csproj = $csproj.FullName }
    }
}
$programs = @($programs | Sort-Object Name)

if ($Only) {
    $programs = @($programs | Where-Object { $_.Name -like "*$Only*" -or $_.Folder -like "*$Only*" })
    if (-not $programs) { throw "Ziadny program nezodpoveda -Only '$Only'." }
}

if (-not $programs) { throw "V $ProgramyRoot sa nenasiel ziadny Exe/WinExe projekt." }

Write-Host "Najdene programy ($($programs.Count)):" -ForegroundColor Cyan
$programs | ForEach-Object { Write-Host ("  - {0}  ({1})" -f $_.Name, $_.Folder) }

$selfContainedFlag = if ($SelfContained) { 'true' } else { 'false' }
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Vsetky programy idu do JEDNEHO priecinka - zdielane DLL (JurhanLib, OmegaLib, DevExpress,
# Kros...) su tam ulozene raz, kazdy program ma vlastny <Name>.exe + <Name>.deps.json
# + <Name>.runtimeconfig.json, ktore sa nekonfliktuju.
if ($Clean -and (Test-Path -LiteralPath $OutputRoot)) {
    Write-Host "Cistim $OutputRoot ..." -ForegroundColor DarkYellow
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}

$results = [System.Collections.Generic.List[object]]::new()

foreach ($program in $programs) {
    Write-Host ""
    Write-Host "==> Publikujem $($program.Name) -> $OutputRoot" -ForegroundColor Cyan

    $publishArgs = @(
        'publish', $program.Csproj,
        '-c', $Configuration,
        '-r', $Runtime,
        '--self-contained', $selfContainedFlag,
        '-o', $OutputRoot
    )
    if ($SatelliteLanguages -and $SatelliteLanguages -ne 'all') {
        $publishArgs += "-p:SatelliteResourceLanguages=$SatelliteLanguages"
    }
    if (-not $ShowWarnings) {
        # Do logu len chyby + suhrn - warningy sa zobrazuju len pri rekompilacii kniznice,
        # takze ich pocet v logu kolise a maskuju skutocne chyby.
        $publishArgs += '-clp:ErrorsOnly;Summary'
    }

    & dotnet @publishArgs
    $ok = ($LASTEXITCODE -eq 0)
    if ($ok) {
        Write-Host "    OK: $($program.Name)" -ForegroundColor Green
    }
    else {
        Write-Host "    ZLYHALO: $($program.Name) (kod $LASTEXITCODE)" -ForegroundColor Red
    }

    $errText = if ($ok) { $null } else { "exit $LASTEXITCODE" }
    $results.Add([pscustomobject]@{ Name = $program.Name; Ok = $ok; Output = $OutputRoot; Error = $errText })
}

$sw.Stop()
$okCount = ($results | Where-Object Ok).Count
Write-Host ""
Write-Host "Hotovo: $okCount/$($results.Count) programov vypublikovanych za $([int]$sw.Elapsed.TotalSeconds)s do $OutputRoot." -ForegroundColor Cyan
$mode = if ($SelfContained) { 'self-contained (runtime zbaleny)' } else { 'framework-dependent (treba .NET 10 Desktop Runtime x64)' }
Write-Host "Rezim: $mode"
$failed = $results | Where-Object { -not $_.Ok }
if ($failed) {
    Write-Host "ZLYHALO:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $($_.Name): $($_.Error)" -ForegroundColor Red }
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
