#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Post-reboot continuation for the ADlab controller22 deployment.

.DESCRIPTION
    Waits for Active Directory Domain Services on the newly promoted domain
    controller to become operational, verifies the local DC, DNS registration,
    SYSVOL and NETLOGON, runs the staged Linux computer enrollment script, and
    removes the startup task only after successful completion.

.NOTES
    Designed to be staged by Bootstrap-ADDS.ps1 under:
      C:\ProgramData\LinuxADProvisioning

    Failure intentionally leaves the scheduled task registered so the workflow
    can retry after a subsequent reboot or manual task start.
#>

[CmdletBinding()]
param ()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$TaskName          = "Complete-Linux-AD-Provisioning"
$ProvisioningRoot  = "C:\ProgramData\LinuxADProvisioning"
$EnrollmentScript  = Join-Path -Path $ProvisioningRoot -ChildPath "LinuxComputerEnrollment.ps1"
$LogFile           = Join-Path -Path $ProvisioningRoot -ChildPath "PostReboot.log"
$DcDiagLog         = Join-Path -Path $ProvisioningRoot -ChildPath "dcdiag.log"
$SuccessMarker     = Join-Path -Path $ProvisioningRoot -ChildPath "ADDS-Provisioning-Complete.txt"
$FailureMarker     = Join-Path -Path $ProvisioningRoot -ChildPath "ADDS-Provisioning-Failed.txt"

$MaximumWait       = New-TimeSpan -Minutes 30
$RetryInterval     = New-TimeSpan -Seconds 10
$Stopwatch         = [Diagnostics.Stopwatch]::StartNew()

function Write-PostRebootLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $entry = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    try {
        Add-Content -LiteralPath $script:LogFile -Value $entry -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to write post-reboot log: $($_.Exception.Message)"
    }

    switch ($Level) {
        "WARNING" { Write-Host $entry -ForegroundColor Yellow }
        "ERROR"   { Write-Host $entry -ForegroundColor Red }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
        default   { Write-Host $entry }
    }
}

function Test-ServiceRunning {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    try {
        $service = Get-Service -Name $Name -ErrorAction Stop
        return $service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running
    }
    catch {
        return $false
    }
}

function Test-ActiveDirectoryReady {
    [CmdletBinding()]
    param ()

    try {
        foreach ($serviceName in @("NTDS", "DNS", "Netlogon")) {
            if (-not (Test-ServiceRunning -Name $serviceName)) {
                return $false
            }
        }

        Import-Module ActiveDirectory -ErrorAction Stop

        $domain = Get-ADDomain -ErrorAction Stop
        $forest = Get-ADForest -ErrorAction Stop
        $dc = Get-ADDomainController -Identity $env:COMPUTERNAME -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($domain.DNSRoot)) { return $false }
        if ([string]::IsNullOrWhiteSpace($forest.Name)) { return $false }
        if ($dc -eq $null) { return $false }

        $srvName = "_ldap._tcp.dc._msdcs.{0}" -f $domain.DNSRoot
        $srv = @(Resolve-DnsName -Name $srvName -Type SRV -ErrorAction Stop)
        if ($srv.Count -eq 0) { return $false }

        $shareNames = @(
            Get-SmbShare -ErrorAction Stop |
                Select-Object -ExpandProperty Name
        )

        if ($shareNames -notcontains "SYSVOL") { return $false }
        if ($shareNames -notcontains "NETLOGON") { return $false }

        return $true
    }
    catch {
        return $false
    }
}

try {
    if (-not (Test-Path -LiteralPath $ProvisioningRoot)) {
        New-Item -ItemType Directory -Path $ProvisioningRoot -Force -ErrorAction Stop | Out-Null
    }

    Remove-Item -LiteralPath $FailureMarker -Force -ErrorAction SilentlyContinue

    Write-PostRebootLog -Message "Starting post-reboot provisioning."
    Write-PostRebootLog -Message "Computer: $env:COMPUTERNAME"
    Write-PostRebootLog -Message "Waiting for AD DS, DNS, Netlogon, AD queries, DNS SRV records, SYSVOL, and NETLOGON."

    while ($Stopwatch.Elapsed -lt $MaximumWait) {
        if (Test-ActiveDirectoryReady) {
            Write-PostRebootLog -Message "Active Directory readiness checks passed." -Level "SUCCESS"
            break
        }

        Write-PostRebootLog -Message (
            "Active Directory is not ready yet. Elapsed: {0:n0} seconds." -f $Stopwatch.Elapsed.TotalSeconds
        ) -Level "WARNING"

        Start-Sleep -Seconds ([int]$RetryInterval.TotalSeconds)
    }

    if (-not (Test-ActiveDirectoryReady)) {
        throw "Active Directory did not become ready within $([int]$MaximumWait.TotalMinutes) minutes."
    }

    Import-Module ActiveDirectory -ErrorAction Stop
    $domain = Get-ADDomain -ErrorAction Stop
    $forest = Get-ADForest -ErrorAction Stop
    $dc = Get-ADDomainController -Identity $env:COMPUTERNAME -ErrorAction Stop

    Write-PostRebootLog -Message "Domain verified: $($domain.DNSRoot)" -Level "SUCCESS"
    Write-PostRebootLog -Message "Forest verified: $($forest.Name)" -Level "SUCCESS"
    Write-PostRebootLog -Message "Domain controller verified: $($dc.HostName)" -Level "SUCCESS"

    Write-PostRebootLog -Message "Running DCDIAG connectivity, advertising, services, and DNS checks."

    $dcDiagOutput = & dcdiag.exe /test:Connectivity /test:Advertising /test:Services /test:DNS 2>&1
    $dcDiagExitCode = $LASTEXITCODE
    $dcDiagOutput | Out-File -LiteralPath $DcDiagLog -Encoding UTF8 -Force

    if ($dcDiagExitCode -ne 0) {
        throw "DCDIAG returned exit code $dcDiagExitCode. Review '$DcDiagLog'."
    }

    Write-PostRebootLog -Message "DCDIAG completed successfully." -Level "SUCCESS"

    if (-not (Test-Path -LiteralPath $EnrollmentScript -PathType Leaf)) {
        throw "Linux enrollment script was not found at '$EnrollmentScript'."
    }

    Write-PostRebootLog -Message "Starting Linux computer enrollment script '$EnrollmentScript'."

    & $EnrollmentScript
    $EnrollmentExitCode = $LASTEXITCODE

    if ($EnrollmentExitCode -ne $null -and $EnrollmentExitCode -ne 0) {
        throw "Linux enrollment script returned exit code $EnrollmentExitCode."
    }

    Write-PostRebootLog -Message "Linux computer enrollment completed successfully." -Level "SUCCESS"

    @"
AD DS post-reboot provisioning completed successfully.
Computer=$env:COMPUTERNAME
Domain=$($domain.DNSRoot)
Forest=$($forest.Name)
DomainController=$($dc.HostName)
Completed=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
DCDIAGExitCode=$dcDiagExitCode
"@ | Set-Content -LiteralPath $SuccessMarker -Encoding UTF8 -Force

    Write-PostRebootLog -Message "Success marker written to '$SuccessMarker'." -Level "SUCCESS"

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-PostRebootLog -Message "Scheduled task '$TaskName' removed after successful completion." -Level "SUCCESS"

    exit 0
}
catch {
    $errorMessage = $_.Exception.Message

    Write-PostRebootLog -Message "Post-reboot provisioning failed: $errorMessage" -Level "ERROR"

    @"
AD DS post-reboot provisioning failed.
Computer=$env:COMPUTERNAME
Time=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Error=$errorMessage

Review:
$LogFile
$DcDiagLog
C:\Windows\debug\dcpromo.log
C:\Windows\debug\dcpromoui.log
"@ | Set-Content -LiteralPath $FailureMarker -Encoding UTF8 -Force

    # Intentionally retain the scheduled task on failure so the workflow can
    # retry on a later boot or when the task is started manually.
    exit 1
}
finally {
    $Stopwatch.Stop()
}
