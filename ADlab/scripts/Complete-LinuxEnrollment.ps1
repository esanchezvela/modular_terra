#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Post-reboot continuation for the ADlab controller22 deployment.

.DESCRIPTION
    Waits for Active Directory Domain Services to become operational, records
    the exact readiness failure while waiting, runs DCDIAG, configures reverse
    DNS, runs Linux computer enrollment, and removes the scheduled task only
    after successful completion.

    Console output and parser/startup errors are captured externally by the
    scheduled-task action in Bootstrap-ADDS.ps1.tftpl.
#>

[CmdletBinding()]
param ()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$TaskName = "Complete-Linux-AD-Provisioning"
$ProvisioningRoot = "C:\ProgramData\LinuxADProvisioning"
$EnrollmentScript = "$ProvisioningRoot\LinuxComputerEnrollment.ps1"
$ReverseZoneScript = "$ProvisioningRoot\CreateReverseZone.ps1"
$LogFile = "$ProvisioningRoot\PostReboot.log"
$ConsoleLog = "$ProvisioningRoot\PostReboot-Console.log"
$ErrorDetailLog = "$ProvisioningRoot\PostReboot-ErrorDetail.log"
$DcDiagLog = "$ProvisioningRoot\dcdiag.log"
$SuccessMarker = "$ProvisioningRoot\ADDS-Provisioning-Complete.txt"
$FailureMarker = "$ProvisioningRoot\ADDS-Provisioning-Failed.txt"

$MaximumWait = New-TimeSpan -Minutes 30
$RetryInterval = New-TimeSpan -Seconds 10
$Stopwatch = [Diagnostics.Stopwatch]::StartNew()

function Write-PostRebootLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $Entry = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    try {
        Add-Content -LiteralPath $script:LogFile -Value $Entry -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning ("Unable to write post-reboot log '{0}': {1}" -f $script:LogFile, $_.Exception.Message)
    }

    switch ($Level) {
        "WARNING" { Write-Host $Entry -ForegroundColor Yellow }
        "ERROR"   { Write-Host $Entry -ForegroundColor Red }
        "SUCCESS" { Write-Host $Entry -ForegroundColor Green }
        default   { Write-Host $Entry }
    }
}

function Get-ActiveDirectoryReadiness {
    [CmdletBinding()]
    param ()

    try {
        foreach ($ServiceName in @("NTDS", "DNS", "Netlogon")) {
            $Service = Get-Service -Name $ServiceName -ErrorAction Stop

            if ($Service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
                return [pscustomobject]@{
                    Ready  = $false
                    Reason = "Service '$ServiceName' is '$($Service.Status)'."
                }
            }
        }

        Import-Module ActiveDirectory -ErrorAction Stop

        $Domain = Get-ADDomain -ErrorAction Stop
        $Forest = Get-ADForest -ErrorAction Stop
        $DomainController = Get-ADDomainController -Identity $env:COMPUTERNAME -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($Domain.DNSRoot)) {
            return [pscustomobject]@{
                Ready  = $false
                Reason = "Get-ADDomain returned an empty DNSRoot."
            }
        }

        if ([string]::IsNullOrWhiteSpace($Forest.Name)) {
            return [pscustomobject]@{
                Ready  = $false
                Reason = "Get-ADForest returned an empty forest name."
            }
        }

        if ($null -eq $DomainController) {
            return [pscustomobject]@{
                Ready  = $false
                Reason = "The local domain controller could not be resolved."
            }
        }

        $SrvName = "_ldap._tcp.dc._msdcs.{0}" -f $Domain.DNSRoot
        $SrvRecords = @(
            Resolve-DnsName -Name $SrvName -Type SRV -ErrorAction Stop
        )

        if ($SrvRecords.Count -eq 0) {
            return [pscustomobject]@{
                Ready  = $false
                Reason = "No SRV records were found for '$SrvName'."
            }
        }

        $ShareNames = @(
            Get-SmbShare -ErrorAction Stop |
                Select-Object -ExpandProperty Name
        )

        if ($ShareNames -notcontains "SYSVOL") {
            return [pscustomobject]@{
                Ready  = $false
                Reason = "The SYSVOL share is not available."
            }
        }

        if ($ShareNames -notcontains "NETLOGON") {
            return [pscustomobject]@{
                Ready  = $false
                Reason = "The NETLOGON share is not available."
            }
        }

        return [pscustomobject]@{
            Ready  = $true
            Reason = "All readiness checks passed."
        }
    }
    catch {
        return [pscustomobject]@{
            Ready  = $false
            Reason = "{0}: {1}" -f $_.Exception.GetType().FullName, $_.Exception.Message
        }
    }
}

function Get-ErrorDetailText {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $Exception = $ErrorRecord.Exception
    $InnerException = "<none>"

    if ($null -ne $Exception.InnerException) {
        $InnerException = $Exception.InnerException.ToString()
    }

    return @"
Timestamp=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Computer=$env:COMPUTERNAME
User=$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
Message=$($Exception.Message)
ExceptionType=$($Exception.GetType().FullName)
FullyQualifiedErrorId=$($ErrorRecord.FullyQualifiedErrorId)
Category=$($ErrorRecord.CategoryInfo)
ScriptName=$($ErrorRecord.InvocationInfo.ScriptName)
Line=$($ErrorRecord.InvocationInfo.ScriptLineNumber)
Position=$($ErrorRecord.InvocationInfo.PositionMessage)
Command=$($ErrorRecord.InvocationInfo.MyCommand)
ScriptStackTrace=$($ErrorRecord.ScriptStackTrace)
InnerException=$InnerException
ErrorRecord=$($ErrorRecord.ToString())
"@
}

try {
    if (-not (Test-Path -LiteralPath $ProvisioningRoot)) {
        New-Item -ItemType Directory -Path $ProvisioningRoot -Force -ErrorAction Stop | Out-Null
    }

    Remove-Item -LiteralPath $FailureMarker -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ErrorDetailLog -Force -ErrorAction SilentlyContinue

    Write-PostRebootLog -Message "Starting post-reboot provisioning."
    Write-PostRebootLog -Message "Computer: $env:COMPUTERNAME"
    Write-PostRebootLog -Message ("Execution identity: {0}" -f [System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    Write-PostRebootLog -Message "Console capture: $ConsoleLog"
    Write-PostRebootLog -Message "Waiting for AD DS, DNS, Netlogon, AD queries, DNS SRV records, SYSVOL, and NETLOGON."

    $Readiness = $null

    while ($Stopwatch.Elapsed -lt $MaximumWait) {
        $Readiness = Get-ActiveDirectoryReadiness

        if ($Readiness.Ready) {
            Write-PostRebootLog -Message "Active Directory readiness checks passed." -Level "SUCCESS"
            break
        }

        Write-PostRebootLog -Message (
            "Active Directory is not ready. Elapsed={0:n0}s. Reason={1}" -f
            $Stopwatch.Elapsed.TotalSeconds,
            $Readiness.Reason
        ) -Level "WARNING"

        Start-Sleep -Seconds ([int]$RetryInterval.TotalSeconds)
    }

    if ($null -eq $Readiness -or -not $Readiness.Ready) {
        $FinalReason = "No readiness result was returned."

        if ($null -ne $Readiness) {
            $FinalReason = $Readiness.Reason
        }

        throw (
            "Active Directory did not become ready within {0} minutes. Last failure: {1}" -f
            [int]$MaximumWait.TotalMinutes,
            $FinalReason
        )
    }

    Import-Module ActiveDirectory -ErrorAction Stop
    $Domain = Get-ADDomain -ErrorAction Stop
    $Forest = Get-ADForest -ErrorAction Stop
    $DomainController = Get-ADDomainController -Identity $env:COMPUTERNAME -ErrorAction Stop

    Write-PostRebootLog -Message "Domain verified: $($Domain.DNSRoot)" -Level "SUCCESS"
    Write-PostRebootLog -Message "Forest verified: $($Forest.Name)" -Level "SUCCESS"
    Write-PostRebootLog -Message "Domain controller verified: $($DomainController.HostName)" -Level "SUCCESS"

    Write-PostRebootLog -Message "Running DCDIAG connectivity, advertising, services, and DNS checks."

    $DcDiagOutput = & dcdiag.exe /test:Connectivity /test:Advertising /test:Services /test:DNS 2>&1
    $DcDiagExitCode = $LASTEXITCODE
    $DcDiagOutput | Out-File -LiteralPath $DcDiagLog -Encoding UTF8 -Force

    if ($DcDiagExitCode -ne 0) {
        throw "DCDIAG returned exit code $DcDiagExitCode. Review '$DcDiagLog'."
    }

    Write-PostRebootLog -Message "DCDIAG completed successfully." -Level "SUCCESS"

    foreach ($RequiredFile in @($ReverseZoneScript, $EnrollmentScript)) {
        if (-not (Test-Path -LiteralPath $RequiredFile -PathType Leaf)) {
            throw "Required provisioning script was not found: $RequiredFile"
        }
    }

    $RequiredModules = @(
        "ActiveDirectory",
        "DnsServer",
        "Az.Accounts",
        "Az.KeyVault"
    )

    foreach ($ModuleName in $RequiredModules) {
        $Module = Get-Module -Name $ModuleName -ListAvailable -ErrorAction SilentlyContinue |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

        if ($null -eq $Module) {
            throw "Required PowerShell module '$ModuleName' is not available."
        }

        Write-PostRebootLog -Message (
            "Required PowerShell module '{0}' version {1} verified." -f
            $ModuleName,
            $Module.Version
        ) -Level "SUCCESS"
    }

    Write-PostRebootLog -Message "Starting reverse DNS zone configuration."
    & $ReverseZoneScript
    Write-PostRebootLog -Message "Reverse DNS zone configuration completed successfully." -Level "SUCCESS"

    Write-PostRebootLog -Message "Starting Linux computer enrollment script '$EnrollmentScript'."
    & $EnrollmentScript
    Write-PostRebootLog -Message "Linux computer enrollment completed successfully." -Level "SUCCESS"

    @"
AD DS post-reboot provisioning completed successfully.
Computer=$env:COMPUTERNAME
Domain=$($Domain.DNSRoot)
Forest=$($Forest.Name)
DomainController=$($DomainController.HostName)
Completed=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
DCDIAGExitCode=$DcDiagExitCode
ConsoleLog=$ConsoleLog
"@ | Set-Content -LiteralPath $SuccessMarker -Encoding UTF8 -Force

    Write-PostRebootLog -Message "Success marker written to '$SuccessMarker'." -Level "SUCCESS"

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-PostRebootLog -Message "Scheduled task '$TaskName' removed after successful completion." -Level "SUCCESS"

    exit 0
}
catch {
    $ErrorRecord = $_
    $ErrorMessage = $ErrorRecord.Exception.Message
    $ErrorDetails = Get-ErrorDetailText -ErrorRecord $ErrorRecord

    try {
        $ErrorDetails | Out-File -LiteralPath $ErrorDetailLog -Encoding UTF8 -Force
    }
    catch {
        Write-Warning ("Unable to write detailed error log '{0}': {1}" -f $ErrorDetailLog, $_.Exception.Message)
    }

    Write-PostRebootLog -Message "Post-reboot provisioning failed: $ErrorMessage" -Level "ERROR"
    Write-PostRebootLog -Message "Detailed error record: $ErrorDetailLog" -Level "ERROR"

    @"
AD DS post-reboot provisioning failed.
Computer=$env:COMPUTERNAME
Time=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Error=$ErrorMessage
ExceptionType=$($ErrorRecord.Exception.GetType().FullName)
Line=$($ErrorRecord.InvocationInfo.ScriptLineNumber)
Command=$($ErrorRecord.InvocationInfo.MyCommand)

Review:
$LogFile
$ConsoleLog
$ErrorDetailLog
$DcDiagLog
C:\Windows\debug\dcpromo.log
C:\Windows\debug\dcpromoui.log
"@ | Set-Content -LiteralPath $FailureMarker -Encoding UTF8 -Force

    exit 1
}
finally {
    if ($null -ne $Stopwatch) {
        $Stopwatch.Stop()
    }
}
