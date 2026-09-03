#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Nasadenie noveho balika sluzieb NA SERVERI (protikus Publish-AllJurhanServices.ps1).
    Na serveri sa spusta z C:\JurhanDeploy, kde je nakopirovany aj zip balik.

      1. Rozbali zip balik (JurhanServiceNew.zip - hlada sa pri skripte, v aktualnom
         priecinku a v C:\JurhanDeploy) do docasneho priecinka a SKONTROLUJE, ze
         obsahuje exe sluzieb. Chybny balik tak zastavi update skor, nez sa cokolvek
         zastavi alebo zmaze.
      2. Zastavi vsetky beziace sluzby "JurhanServiceNew_*".
      3. PREPISE subory zo zipu do $RootPath (default C:\JurhanServiceNew).
         Nic sa nemaze ani nezalohuje - podadresare a subory, ktore v zipe nie su
         (pracovne priecinky, logy, konfiguracie...), ostavaju nedotknute.
      4. Znova spusti sluzby, ktore pred aktualizaciou bezali (s -StartAll vsetky
         zaregistrovane).

    Registraciu sluzieb NEMENI - sluzby musia byt uz zaregistrovane cez
    Install-AllJurhanServices.ps1. Ak nie su, balik sa len rozbali a skript
    na to upozorni.

.PARAMETER ZipPath
    Cesta k zip baliku vytvorenemu skriptom Publish-AllJurhanServices.ps1.
    Ak nie je zadana, JurhanServiceNew.zip sa hlada postupne: v priecinku tohto
    skriptu, v aktualnom priecinku a v C:\JurhanDeploy - pouzije sa prvy najdeny.
    Balik obsahuje korenovy priecinok (JurhanServiceNew\...), skript to ale
    zvladne aj bez neho.

.PARAMETER RootPath
    Priecinok nasadenia (default C:\JurhanServiceNew). Zhoduje sa s -RootPath
    v Install-AllJurhanServices.ps1 a -OutputRoot v Publish-AllJurhanServices.ps1.

.PARAMETER StartAll
    Po rozbaleni spusti VSETKY zaregistrovane sluzby "JurhanServiceNew_*", nie len
    tie, ktore pred aktualizaciou bezali. Bez neho sa umyselne zastavena sluzba
    aktualizaciou nespusti.

.EXAMPLE
    .\Update-AllJurhanServices.ps1

.EXAMPLE
    .\Update-AllJurhanServices.ps1 -ZipPath 'D:\Prenos\JurhanServiceNew.zip' -StartAll
#>
[CmdletBinding()]
param(
    [string]$ZipPath,
    [string]$RootPath = 'C:\JurhanServiceNew',
    [switch]$StartAll
)

$ErrorActionPreference = 'Stop'

# Cely priebeh aktualizacie sa loguje do suboru (netreba kopirovat z okna - staci podhodit subor).
$logPath = Join-Path $PSScriptRoot ("Update_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

$updateError = $null
try {

# --- Najdenie zip balika ----------------------------------------------------------
# Bez -ZipPath sa JurhanServiceNew.zip hlada postupne: pri tomto skripte, v aktualnom
# priecinku a v C:\JurhanDeploy (tam ho uklada Publish-AllJurhanServices.ps1).
if (-not $ZipPath) {
    $zipName    = 'JurhanServiceNew.zip'
    $candidates = @(@($PSScriptRoot, (Get-Location).Path, 'C:\JurhanDeploy') |
                    Where-Object { $_ } |
                    Select-Object -Unique |
                    ForEach-Object { Join-Path $_ $zipName })
    $ZipPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $ZipPath) {
        throw ("Zip balik $zipName sa nenasiel na ziadnom z tychto miest:`n - " + ($candidates -join "`n - ") +
               "`nSkopiruj ho vedla tohto skriptu, alebo zadaj cestu ako prvy argument: Update-AllJurhanServices.bat C:\cesta\$zipName")
    }
    Write-Host "Zip balik: $ZipPath"
}
elseif (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "Zip balik nenajdeny: $ZipPath"
}

# --- 1. Rozbal zip do docasneho priecinka a skontroluj ho -------------------------
# Rozbaluje sa ESTE PRED zastavenim sluzieb: ked je balik poskodeny alebo ma zlu
# strukturu, update tu skonci a sluzby bezia dalej nedotknute.
#
# Publish bali archiv VRATANE korenoveho priecinka (JurhanServiceNew\...). Zisti sa,
# ci maju vsetky polozky zipu jediny spolocny korenovy priecinok (nazov je jedno).
# POZOR na oddelovace: .NET Framework (Windows PowerShell 5.1) zapisuje nazvy
# poloziek so '\', novsi .NET s '/' - preto sa normalizuju. Povodna verzia tohto
# skriptu porovnavala len '/' a balik z 5.1 rozbalila o uroven hlbsie
# (C:\JurhanServiceNew\JurhanServiceNew\...), takze sluzby nenasli svoje exe.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipRootName = $null
$zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
    if ($zip.Entries.Count -eq 0) { throw "Zip balik $ZipPath je prazdny." }
    $names    = @($zip.Entries | ForEach-Object { ($_.FullName -replace '\\', '/').TrimStart('/') } | Where-Object { $_ })
    $topFiles = @($names | Where-Object { $_ -notmatch '/' })
    $topDirs  = @($names | ForEach-Object { ($_ -split '/')[0] } | Select-Object -Unique)
    if ($topFiles.Count -eq 0 -and $topDirs.Count -eq 1) { $zipRootName = $topDirs[0] }
}
finally { $zip.Dispose() }

$parentDir = Split-Path -Parent $RootPath
if (-not (Test-Path -LiteralPath $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

Write-Host ""
Write-Host "Rozbalujem $ZipPath ..." -ForegroundColor Cyan
# ZipFile priamo z .NET - Expand-Archive je na balik tejto velkosti radovo pomalsi.
# Docasny priecinok je na tom istom disku ako $RootPath, takze finalny presun
# je len rename (okamzity).
$tempExtract = Join-Path $parentDir ((Split-Path -Leaf $RootPath) + '_rozbalovanie')
if (Test-Path -LiteralPath $tempExtract) { Remove-Item -LiteralPath $tempExtract -Recurse -Force }
[System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $tempExtract)

# Novy obsah = vnutorny korenovy priecinok zipu (ak existuje), inak cely temp.
$newContentDir = if ($zipRootName) { Join-Path $tempExtract $zipRootName } else { $tempExtract }

# Kontrola struktury PRED zastavenim sluzieb: exe musia byt priamo v koreni noveho
# obsahu, inak by sluzby nenastartovali ("Cannot start service" bez detailov).
$exeCount = @(Get-ChildItem -LiteralPath $newContentDir -Filter 'JurhanService_*.exe' -File -ErrorAction SilentlyContinue).Count
if ($exeCount -eq 0) {
    Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    throw "V zip baliku nie je v koreni ziadne JurhanService_*.exe - balik ma inu strukturu, nez sa cakalo. Sluzby sa nezastavuju."
}
Write-Host "    OK: rozbalene ($exeCount exe sluzieb)." -ForegroundColor Green

# --- 2. Zastav beziace sluzby -----------------------------------------------------
# SCM nazvy sluzieb maju prefix "JurhanServiceNew_" (vid Install-AllJurhanServices.ps1).
# Zoznam sa berie z SCM (nie napevno), takze pridanie/odobratie sluzby tento skript nerozbije.
$ServicePrefix = 'JurhanServiceNew_'
$services      = @(Get-Service -Name "$ServicePrefix*" -ErrorAction SilentlyContinue)
$runningBefore = @($services | Where-Object { $_.Status -eq 'Running' })

if (-not $services) {
    Write-Warning "Na tomto stroji nie je zaregistrovana ziadna sluzba '$ServicePrefix*'. Balik sa len rozbali - sluzby potom zaregistruj cez Install-AllJurhanServices.ps1."
}

Write-Host ""
if ($runningBefore) {
    Write-Host "Zastavujem $($runningBefore.Count) beziacich sluzieb:" -ForegroundColor Cyan
    foreach ($svc in $runningBefore) {
        Write-Host "   - $($svc.Name)"
        Stop-Service -Name $svc.Name -Force
    }
}
else {
    Write-Host "Ziadna sluzba '$ServicePrefix*' prave nebezi - nie je co zastavovat."
}

# Stop-Service caka len na stav 'Stopped' v SCM; proces moze exe/dll drzat este
# chvilu po nom. Navyse moze v priecinku bezat manualne spusteny JurhanServiceRun.exe.
# Pred prepisom suborov sa preto pocka, kym vsetky procesy z $RootPath skoncia.
if (Test-Path -LiteralPath $RootPath) {
    $rootPrefix = $RootPath.TrimEnd('\') + '\'
    $deadline   = (Get-Date).AddSeconds(30)
    do {
        $locking = @(Get-Process -ErrorAction SilentlyContinue |
                     Where-Object { $_.Path -and $_.Path.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) })
        if (-not $locking) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    if ($locking) {
        $names = ($locking | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join ', '
        throw "V priecinku $RootPath stale bezia procesy: $names. Zavri ich (napr. JurhanServiceRun.exe) a spusti skript znova."
    }
}

# --- 3. Prepis subory zo zipu do $RootPath ------------------------------------------
# LEN prepis: co je v zipe, sa skopiruje cez existujuce subory; co v zipe nie je
# (pracovne podadresare, logy, konfiguracie...), ostava nedotknute. Preto robocopy
# BEZ /PURGE. Copy-Item -Recurse sa nepouziva umyselne - pri existujucich
# podadresaroch (sk, runtimes) by ich zanoril do seba.
Write-Host ""
Write-Host "Prepisujem subory z balika do $RootPath ..." -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $RootPath)) {
    New-Item -ItemType Directory -Path $RootPath -Force | Out-Null
}
# /E = aj podadresare, /NFL /NDL = nevypisuj tisice suborov (suhrn ostava),
# /R:2 /W:2 = pri zamknutom subore len 2 kratke opakovania namiesto default milionu.
& robocopy $newContentDir $RootPath /E /NFL /NDL /R:2 /W:2
if ($LASTEXITCODE -ge 8) {
    throw "Kopirovanie noveho obsahu zlyhalo (robocopy kod $LASTEXITCODE). Sluzby sa nespustaju - obsah $RootPath moze byt nekompletny."
}
Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "    OK: subory prepisane." -ForegroundColor Green

# --- 4. Znova spusti sluzby ---------------------------------------------------------
$toStart = if ($StartAll) { $services } else { $runningBefore }
$failed  = [System.Collections.Generic.List[object]]::new()

Write-Host ""
if ($toStart) {
    Write-Host "Spustam $($toStart.Count) sluzieb:" -ForegroundColor Cyan
    foreach ($svc in $toStart) {
        try {
            Start-Service -Name $svc.Name
            Write-Host "   - $($svc.Name): OK" -ForegroundColor Green
        }
        catch {
            # Start-Service vracia genericke "Cannot start service..." - skutocny dovod
            # (napr. 1053 = proces hned spadol) byva az vo vnutornej vynimke.
            $reason = $_.Exception.Message
            if ($_.Exception.InnerException) { $reason += " / " + $_.Exception.InnerException.Message }
            Write-Host "   - $($svc.Name): ZLYHALO - $reason" -ForegroundColor Red
            $failed.Add($svc.Name)
        }
    }
}
elseif ($services) {
    Write-Host "Pred aktualizaciou nebezala ziadna sluzba, takze sa ziadna nespusta (vsetky spustis cez -StartAll)." -ForegroundColor DarkYellow
}

# --- Suhrn --------------------------------------------------------------------------
Write-Host ""
Write-Host "Hotovo: balik nasadeny do $RootPath, spustenych $($toStart.Count - $failed.Count)/$($toStart.Count) sluzieb." -ForegroundColor Cyan
if ($failed.Count -gt 0) {
    # Najcastejsia pricina hromadneho zlyhania: balik je framework-dependent
    # (nema pribaleny runtime) a na serveri chyba .NET 10 Desktop Runtime (x64).
    # Exe vtedy hned po starte spadne a SCM vrati genericke "Cannot start service".
    if (-not (Test-Path -LiteralPath (Join-Path $RootPath 'hostfxr.dll'))) {
        $desktopRuntime = @()
        try { $desktopRuntime = @(& dotnet --list-runtimes 2>$null | Where-Object { $_ -like 'Microsoft.WindowsDesktop.App 10.*' }) } catch { }
        if (-not $desktopRuntime) {
            Write-Host ""
            Write-Host "Balik je framework-dependent a na tomto stroji sa nenasiel .NET 10 Desktop Runtime (x64) - to je najskor pricina zlyhania." -ForegroundColor Red
            Write-Host "Riesenie: nainstaluj '.NET Desktop Runtime 10 (x64)' z https://dotnet.microsoft.com/download/dotnet/10.0" -ForegroundColor Red
            Write-Host "a potom sluzby spusti: Get-Service JurhanServiceNew_* | Start-Service" -ForegroundColor Red
            Write-Host "(Alternativa: publishni balik so selfcontained - Publish-AllJurhanServices.bat clean selfcontained.)" -ForegroundColor Red
        }
    }
    throw "Nepodarilo sa spustit sluzby: $($failed -join ', '). Pozri ich .err logy v $RootPath."
}

}
catch {
    # Chyba sa vypise TU, este pred Stop-Transcript - inak by v logu vobec nebola
    # (throw by sa zobrazil az po ukonceni transcriptu, len v okne).
    $updateError = $_
    Write-Host ""
    Write-Host "CHYBA: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host "LOG ULOZENY DO SUBORU: $logPath" -ForegroundColor Yellow
    Write-Host "Tento subor podhod (netreba kopirovat text z okna)." -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch { }
}

if ($updateError) { exit 1 }
