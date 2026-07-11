#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Registruje jednu novu .NET 10 sluzbu ako Windows Service pod SCM nazvom "JurhanServiceNew_*".

    Nahradza stary installutil.exe / System.Configuration.Install.Installer mechanizmus
    (JurhanLib.Services.ProjectInstallerBase), ktory na .NET 10 uz neexistuje
    (System.ServiceProcess.ServiceInstaller / ServiceProcessInstaller nie su podporovane).
    Modernou nahradou je priame volanie sc.exe pri nasadeni.

    Pozn.: SCM nazov (-Name, napr. JurhanServiceNew_ImportFaktur) sa lisi od nazvu exe
    suboru (JurhanService_ImportFaktur.exe) - exe/assembly sa nepremenovali. Preto pri
    davkovom nasadeni treba -ExePath zadat explicitne (vid Install-AllJurhanServices.ps1).
    Prefix "New" umoznuje koexistenciu so starymi povodnymi sluzbami "JurhanService_*".

.PARAMETER Name
    SCM nazov sluzby (napr. "JurhanServiceNew_AktualizaciaZasob"). Musi sa zhodovat
    s hodnotou vracanou z Program.<nazovServicy|serviceName> / Service.Name() v danom
    projekte, inak sa nezhodne register sluzby s tym, co si aplikacia mysli, ze sa vola.

.PARAMETER ExePath
    Plna cesta k .exe suboru sluzby (exe sa vola JurhanService_<X>.exe, NIE New).
    Ak nie je zadana, odvodi sa ako "<RootPath>\<Name>\<Name>.exe" - pozor, to pri "New"
    SCM nazve nesedi s exe nazvom, preto pri tychto sluzbach zadavaj -ExePath explicitne.

.PARAMETER RootPath
    Korenovy adresar nasadenia (default C:\JurhanService), pouzije sa len ak ExePath
    nie je zadana.

.PARAMETER Credential
    Konto, pod ktorym ma sluzba bezat (Log On As). Ak nie je zadane, vypyta sa
    interaktivne - heslo sa NEUKLADA ani neposiela ako cisty text na prikazovy riadok
    (na rozdiel od povodneho ProjectInstallerBase, ktory mal heslo natvrdo v skompilovanom
    kode v JurhanModels.Constants.JurhanServerUserTulejaPassword).

.PARAMETER DisplayName
    Zobrazovany nazov v services.msc. Default = Name.

.PARAMETER Description
    Popis sluzby. Default = Name.

.PARAMETER StartupType
    auto (default) / demand / disabled.

.EXAMPLE
    .\Install-JurhanService.ps1 -Name JurhanServiceNew_ImportFaktur -ExePath 'C:\JurhanServiceNew\JurhanService_ImportFaktur\JurhanService_ImportFaktur.exe'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [string]$ExePath,

    [string]$RootPath = 'C:\JurhanService',

    [System.Management.Automation.PSCredential]$Credential,

    # Ak je zadane, sluzba pobezi pod vstavanym kontom LocalSystem (bez hesla) -
    # vhodne na rychly lokalny test. Pre ostre nasadenie pouzi realne -Credential.
    [switch]$LocalSystem,

    [string]$DisplayName = $Name,

    [string]$Description = $Name,

    [ValidateSet('auto', 'demand', 'disabled')]
    [string]$StartupType = 'auto'
)

$ErrorActionPreference = 'Stop'

# Udeli kontu pravo "Log on as a service" (SeServiceLogonRight) cez LSA API. Bez neho
# sluzba pod pouzivatelskym kontom nenastartuje (chyba 1069 "logon failure"). sc.exe to nerobi.
function Grant-ServiceLogonRight {
    param([Parameter(Mandatory)][string]$Account)
    $acct = $Account
    if ($acct -like '.\*') { $acct = "$env:COMPUTERNAME\" + $acct.Substring(2) }
    try {
        $sid = (New-Object System.Security.Principal.NTAccount($acct)).Translate([System.Security.Principal.SecurityIdentifier])
    }
    catch {
        Write-Warning "Nepodarilo sa prelozit konto '$acct' na SID - pravo 'Log on as a service' udel rucne (secpol.msc)."
        return
    }
    $sidBytes = New-Object byte[] $sid.BinaryLength
    $sid.GetBinaryForm($sidBytes, 0)

    if (-not ([System.Management.Automation.PSTypeName]'LsaHelper.Privilege').Type) {
        Add-Type -Namespace LsaHelper -Name Privilege -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }
[StructLayout(LayoutKind.Sequential)]
struct LSA_OBJECT_ATTRIBUTES { public int Length; public IntPtr RootDirectory; public IntPtr ObjectName; public int Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService; }
[DllImport("advapi32.dll", SetLastError=true)]
static extern int LsaOpenPolicy(IntPtr SystemName, ref LSA_OBJECT_ATTRIBUTES ObjectAttributes, int DesiredAccess, out IntPtr PolicyHandle);
[DllImport("advapi32.dll", SetLastError=true)]
static extern int LsaAddAccountRights(IntPtr PolicyHandle, byte[] AccountSid, LSA_UNICODE_STRING[] UserRights, int CountOfRights);
[DllImport("advapi32.dll")]
static extern int LsaClose(IntPtr PolicyHandle);
[DllImport("advapi32.dll")]
static extern int LsaNtStatusToWinError(int Status);
public static void AddRight(byte[] sid, string right) {
    LSA_OBJECT_ATTRIBUTES oa = new LSA_OBJECT_ATTRIBUTES();
    IntPtr policy;
    int st = LsaOpenPolicy(IntPtr.Zero, ref oa, 0x00000010 | 0x00000020, out policy);
    if (st != 0) throw new System.ComponentModel.Win32Exception(LsaNtStatusToWinError(st));
    try {
        LSA_UNICODE_STRING[] rights = new LSA_UNICODE_STRING[1];
        rights[0].Buffer = Marshal.StringToHGlobalUni(right);
        rights[0].Length = (ushort)(right.Length * 2);
        rights[0].MaximumLength = (ushort)((right.Length + 1) * 2);
        st = LsaAddAccountRights(policy, sid, rights, 1);
        Marshal.FreeHGlobal(rights[0].Buffer);
        if (st != 0) throw new System.ComponentModel.Win32Exception(LsaNtStatusToWinError(st));
    } finally { LsaClose(policy); }
}
'@
    }
    try {
        [LsaHelper.Privilege]::AddRight($sidBytes, 'SeServiceLogonRight')
        Write-Host "Kontu '$acct' udelene pravo 'Log on as a service'."
    }
    catch {
        Write-Warning "Nepodarilo sa udelit 'Log on as a service' kontu '$acct': $($_.Exception.Message). Udel ho rucne (secpol.msc)."
    }
}

if (-not $ExePath) {
    $ExePath = Join-Path $RootPath (Join-Path $Name "$Name.exe")
}

if (-not (Test-Path -LiteralPath $ExePath)) {
    throw "Exe subor sluzby nebol najdeny: $ExePath"
}

if (-not $LocalSystem -and -not $Credential) {
    $Credential = Get-Credential -Message "Konto (Log On As) pre sluzbu '$Name' (alebo spusti s -LocalSystem)"
}

$existing = Get-Service -Name $Name -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Sluzba '$Name' uz existuje, zastavujem a mazem pred re-instalaciou..."
    if ($existing.Status -ne 'Stopped') {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    }
    & sc.exe delete $Name | Out-Null
    Start-Sleep -Seconds 1
}

# sc.exe vyzaduje presne tento format ("kluc= hodnota", medzera za "="), inak zlyha bez zjavnej priciny.
if ($LocalSystem) {
    $account = 'LocalSystem'
    & sc.exe create $Name binPath= "`"$ExePath`"" start= $StartupType obj= "LocalSystem" DisplayName= "$DisplayName"
}
else {
    $account = $Credential.UserName
    # Normalizuj konto na kanonicky tvar DOMENA\user. sc.exe obj= bare meno (napr. "kros.support")
    # chape ako lokalne (.\kros.support) -> pri domenovom konte zlyha s 1057. SID round-trip
    # doplni spravnu domenu (ALLTOTRANS\kros.support), takze mozes zadat aj holy nazov.
    try {
        $account = (New-Object System.Security.Principal.NTAccount($account)).Translate([System.Security.Principal.SecurityIdentifier]).Translate([System.Security.Principal.NTAccount]).Value
    }
    catch {
        Write-Warning "Konto '$account' sa nepodarilo normalizovat na DOMENA\user - pouzivam ako je zadane."
    }
    $plainPassword = $Credential.GetNetworkCredential().Password
    Grant-ServiceLogonRight -Account $account
    Write-Host "Vytvaram sluzbu '$Name' pod kontom '$account' ..."
    & sc.exe create $Name binPath= "`"$ExePath`"" start= $StartupType obj= "$account" password= "$plainPassword" DisplayName= "$DisplayName"
}
if ($LASTEXITCODE -ne 0) {
    if ($LASTEXITCODE -eq 1057) {
        throw "sc.exe create zlyhalo (1057): neplatne konto alebo HESLO. Konto '$account' existuje, takze najpravdepodobnejsie je zle HESLO. Skontroluj heslo a spusti znova."
    }
    throw "sc.exe create zlyhalo s kodom $LASTEXITCODE"
}

& sc.exe description $Name "$Description" | Out-Null

Write-Host "Sluzba '$Name' bola zaregistrovana (exe: $ExePath, konto: $account, start: $StartupType)." -ForegroundColor Green
Write-Host "Spustenie: Start-Service -Name '$Name'"
