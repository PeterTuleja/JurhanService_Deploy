#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Zaregistruje vsetkych 17 novych .NET 10 sluzieb naraz pod jednym spolocnym kontom.

    SCM nazov sluzby ma prefix "JurhanServiceNew_" (napr. JurhanServiceNew_ImportFaktur),
    aby nove sluzby mohli KOEXISTOVAT so starymi povodnymi (net48, "JurhanService_") na
    tom istom serveri. Ak nove nasadenie zlyha, stare "JurhanService_" sluzby ostavaju
    zaregistrovane a daju sa okamzite nastartovat.

    Exe subory sa NEPREMENOVALI - ostavaju "JurhanService_<X>.exe" (nazov assembly), takze
    cesta k exe vychadza z povodneho nazvu, ale SCM registracia je pod "JurhanServiceNew_<X>".

.PARAMETER RootPath
    Spolocny adresar nasadenia (default C:\JurhanServiceNew) - vsetky sluzby su v jednom
    priecinku. Konvencia exe: <RootPath>\<JurhanService_X>.exe

.PARAMETER Credential
    Konto, pod ktorym maju sluzby bezat. Ak nie je zadane, vypyta sa raz interaktivne
    a pouzije sa pre vsetky sluzby.

.NOTES
    PREREKVIZITA - Access Database Engine (x64):
    Sluzby pristupuju k Omega .mdb databazam cez provider Microsoft.ACE.OLEDB.12.0
    (net10 procesy su x64). Na cielovom stroji musi byt nainstalovany 64-bitovy
    "Microsoft Access Database Engine 2016 Redistributable" - bez neho pristup k .mdb
    padne az za behu chybou "provider is not registered on the local machine".
    (Stary Net48 kod bezal x86 cez Jet 4.0, ktory bol sucastou Windows - preto to
    predtym fungovalo bez instalacie.)

.EXAMPLE
    .\Install-AllJurhanServices.ps1
#>
[CmdletBinding()]
param(
    [string]$RootPath = 'C:\JurhanServiceNew',
    [System.Management.Automation.PSCredential]$Credential,
    # Vsetky sluzby pobezia pod LocalSystem (bez hesla) - na rychly lokalny test.
    [switch]$LocalSystem
)

$ErrorActionPreference = 'Stop'

# Cely priebeh instalacie sa loguje do suboru (netreba kopirovat z okna - staci podhodit subor).
$logPath = Join-Path $PSScriptRoot ("Install_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {

# Zakladne (exe) nazvy - zhoduju sa s nazvami assembly/exe suborov (JurhanService_<X>.exe).
# SCM nazov sa z nich odvodi pridanim prefixu "New" (JurhanService_ -> JurhanServiceNew_),
# aby nove sluzby koexistovali so starymi. Tento SCM nazov MUSI zodpovedat runtime hodnote
# z Program.<serviceName|nazovServicy> v danom projekte.
$ExeBaseNames = @(
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

# Prehlad PRED instalaciou - nech je jasne, ze sa registruju NOVE (JurhanServiceNew_*) sluzby
# a stare povodne (JurhanService_*) ostavaju nedotknute.
Write-Host ""
Write-Host "Zaregistruju sa tieto NOVE sluzby (SCM nazov = JurhanServiceNew_*):" -ForegroundColor Cyan
foreach ($exeBase in $ExeBaseNames) {
    $scm = $exeBase -replace '^JurhanService_', 'JurhanServiceNew_'
    Write-Host ("   {0,-40}  (exe: {1}.exe)" -f $scm, $exeBase)
}
Write-Host "Stare povodne sluzby 'JurhanService_*' sa NEDOTKNU (zostavaju spustitelne pre rollback)." -ForegroundColor DarkGreen
Write-Host ""

if (-not $LocalSystem -and -not $Credential) {
    $Credential = Get-Credential -Message "Spolocne konto (Log On As) pre vsetky JurhanServiceNew_* sluzby (alebo spusti s -LocalSystem)"
}

$installScript = Join-Path $PSScriptRoot 'Install-JurhanService.ps1'

# List + .Add() - aby sa stdout z sc.exe (vo volanom skripte) NEzbieral do vysledkov.
$results = [System.Collections.Generic.List[object]]::new()

foreach ($exeBase in $ExeBaseNames) {
    # SCM nazov = povodny nazov s prefixom "New"; exe cesta vychadza z povodneho nazvu.
    # Vsetky sluzby su v JEDNOM priecinku ($RootPath), takze exe je priamo tam.
    $scmName = $exeBase -replace '^JurhanService_', 'JurhanServiceNew_'
    $exePath = Join-Path $RootPath "$exeBase.exe"
    try {
        if ($LocalSystem) {
            & $installScript -Name $scmName -ExePath $exePath -LocalSystem
        }
        else {
            & $installScript -Name $scmName -ExePath $exePath -Credential $Credential
        }
        $results.Add([pscustomobject]@{ Name = $scmName; Ok = $true; Error = $null })
    }
    catch {
        Write-Warning "Zlyhala instalacia '$scmName': $($_.Exception.Message)"
        $results.Add([pscustomobject]@{ Name = $scmName; Ok = $false; Error = $_.Exception.Message })
    }
}

$failed = $results | Where-Object { -not $_.Ok }
Write-Host ""
Write-Host "Hotovo: $($results.Count - $failed.Count)/$($results.Count) sluzieb zaregistrovanych." -ForegroundColor Cyan
if ($failed) {
    Write-Host "Zlyhalo:" -ForegroundColor Red
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
