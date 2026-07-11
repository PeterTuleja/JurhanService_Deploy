#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Odregistruje Windows Service (companion k Install-JurhanService.ps1).

.PARAMETER Name
    SCM nazov sluzby. Pre nove .NET 10 sluzby "JurhanServiceNew_<X>", pre stare povodne
    "JurhanService_<X>". POZOR: nezamenit - odinstaluj len to, co naozaj chces.

.EXAMPLE
    .\Uninstall-JurhanService.ps1 -Name JurhanServiceNew_AktualizaciaZasob
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

$existing = Get-Service -Name $Name -ErrorAction SilentlyContinue
if (-not $existing) {
    Write-Host "Sluzba '$Name' nie je zaregistrovana, nic nerobim."
    return
}

if ($existing.Status -ne 'Stopped') {
    Stop-Service -Name $Name -Force
}

& sc.exe delete $Name
if ($LASTEXITCODE -ne 0) {
    throw "sc.exe delete zlyhalo s kodom $LASTEXITCODE"
}

Write-Host "Sluzba '$Name' bola odregistrovana." -ForegroundColor Green
