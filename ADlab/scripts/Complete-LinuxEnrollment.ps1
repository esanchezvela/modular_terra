#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Post-reboot continuation script. Waits for AD DS to become ready, then
    runs the Linux computer enrollment provisioning script.

.NOTES
    Corrected version. Fixes applied vs. the previous draft:
      1. The enrollment script must use 'return' rather than 'exit' when it
         has nothing to do. 'exit' terminates the entire powershell.exe
         process this script runs in, which would prevent the success log
         entry and the Unregister-ScheduledTask call below from running,
         causing the task to keep firing on every future boot.
      2. The scheduled task is only unregistered after a fully successful
         run; any failure leaves it registered so its restart settings (or
         the next reboot) can retry.
#>

[CmdletBinding()]
param ()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$TaskName = "Complete-Linux-AD-Provisioning"

$ProvisioningRoot = "C:\ProgramData\LinuxADProvisioning"
$EnrollmentScript = Join-Path -Path $ProvisioningRoot -ChildPath "New-LinuxComputerEnrollment.ps1"
$LogFile          = Join-Path -Path $ProvisioningRoot -ChildPath "PostReboot.log"

$MaximumWait = New-TimeSpan -Minutes 30
$Stopwatch   = [Diagnostics.Stopwatch]::StartNew()

function Write-PostRebootLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $Entry = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    Add-Content -LiteralPath $script:LogFile -Value $Entry -Encoding UTF8 -ErrorAction SilentlyContinue

    Write-Host $Entry
}

function Test-ActiveDirectoryReady {
    [CmdletBinding()]
    param ()

    $Ntds = Get-Service -Name "NTDS" -ErrorAction SilentlyContinue
    $Adws = Get-Service -Name "ADWS" -ErrorAction SilentlyContinue

    $NtdsReady = ($null -ne $Ntds -and $Ntds.Status -eq "Running")
    $AdwsReady = ($null -ne $Adws -and $Adws.Status -eq "Running")

    if (-not ($NtdsReady -and $AdwsReady)) {
        return $false
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        $Domain = Get-ADDomain -ErrorAction Stop

        return $null -ne $Domain
    }
    catch {
        return $false
    }
}

try {
    Write-PostRebootLog "Starting post-reboot provisioning."

    if (-not (Test-Path -LiteralPath $EnrollmentScript -PathType Leaf)) {
        throw "Enrollment script was not found: $EnrollmentScript"
    }

    while (-not (Test-ActiveDirectoryReady) -and $Stopwatch.Elapsed -lt $MaximumWait) {
        Write-PostRebootLog "Active Directory is not ready. Retrying in 15 seconds." -Level "WARNING"

        Start-Sleep -Seconds 15
    }

    if (-not (Test-ActiveDirectoryReady)) {
        throw "Active Directory did not become ready within 30 minutes."
    }

    Write-PostRebootLog "Active Directory is ready."

    foreach ($ModuleName in @("ActiveDirectory", "Az.Accounts", "Az.KeyVault")) {
        if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
            throw "Required PowerShell module is unavailable: $ModuleName"
        }

        Import-Module -Name $ModuleName -ErrorAction Stop
    }

    Write-PostRebootLog "Starting Linux computer enrollment."

    #
    # Note: New-LinuxComputerEnrollment.ps1 must use 'return' (not 'exit')
    # for its "nothing to do" early-out path, since 'exit' would terminate
    # this entire powershell.exe process, including the code below.
    #
    & $EnrollmentScript

    Write-PostRebootLog "Linux computer enrollment completed successfully."

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop

    Write-PostRebootLog "Post-reboot scheduled task removed successfully."
}
catch {
    Write-PostRebootLog -Message "Post-reboot provisioning failed: $($_.Exception.Message)" -Level "ERROR"

    #
    # Keep the scheduled task registered so its restart settings or the next
    # reboot can retry the operation.
    #
    throw
}
finally {
    $Stopwatch.Stop()
}
